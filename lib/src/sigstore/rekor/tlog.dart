import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../crypto/der.dart';
import '../crypto/ecdsa.dart';
import '../x509/certificate.dart';
import 'merkle.dart';

/// Result of verifying a Rekor transparency log entry.
final class RekorVerificationResult {
  /// Whether the entry cryptographic proofs are fully valid.
  final bool isValid;

  /// The verified log index.
  final int logIndex;

  /// The timestamp at which the entry was integrated into the log.
  final DateTime integratedTime;

  /// Detailed error messages if verification failed.
  final List<String> errors;

  RekorVerificationResult({
    required this.isValid,
    required this.logIndex,
    required this.integratedTime,
    this.errors = const [],
  });
}

/// Verifier for Rekor transparency log entries in Sigstore bundles.
final class RekorVerifier {
  RekorVerifier._();

  /// Verifies a single transparency log entry against the trusted root Rekor public keys,
  /// the signing certificate, and the expected payload hash and signature.
  ///
  /// Throws a [FormatException] if [tlogEntryMap] is malformed.
  ///
  /// It is an error if [tlogEntryMap] is empty.
  static RekorVerificationResult verifyEntry({
    required Map<String, dynamic> tlogEntryMap,
    required Map<String, dynamic> trustedRootJson,
    required FulcioCertificate signingCert,
    required Uint8List expectedPayloadHash,
    required Uint8List expectedSignatureBytes,
  }) {
    ArgumentError.checkNotNull(tlogEntryMap, 'tlogEntryMap');
    ArgumentError.checkNotNull(trustedRootJson, 'trustedRootJson');
    ArgumentError.checkNotNull(signingCert, 'signingCert');
    ArgumentError.checkNotNull(expectedPayloadHash, 'expectedPayloadHash');
    ArgumentError.checkNotNull(
      expectedSignatureBytes,
      'expectedSignatureBytes',
    );

    final errors = <String>[];

    final canonBodyB64 = tlogEntryMap['canonicalizedBody'] as String?;
    if (canonBodyB64 == null) {
      return RekorVerificationResult(
        isValid: false,
        logIndex: -1,
        integratedTime: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        errors: ['Missing canonicalizedBody in tlog entry'],
      );
    }

    final canonBodyBytes = base64Decode(canonBodyB64);
    final canonBodyJson =
        jsonDecode(utf8.decode(canonBodyBytes)) as Map<String, dynamic>;

    // 1. Verify consistency of canonical body with artifact hash, signature, and certificate
    final spec = canonBodyJson['spec'] as Map<String, dynamic>?;
    if (spec == null) {
      errors.add('Missing spec in canonicalized body');
    } else {
      final dataObj = spec['data'] as Map<String, dynamic>?;
      final hashObj = dataObj?['hash'] as Map<String, dynamic>?;
      final loggedHashHex = hashObj?['value'] as String?;
      final expectedHashHex = DerUtils.hexEncode(expectedPayloadHash);

      if (loggedHashHex?.toLowerCase() != expectedHashHex.toLowerCase()) {
        errors.add(
          'Rekor entry data hash ($loggedHashHex) does not match artifact hash ($expectedHashHex)',
        );
      }

      final sigObj = spec['signature'] as Map<String, dynamic>?;
      final loggedSigContent = sigObj?['content'] as String?;
      if (loggedSigContent != null) {
        final loggedSigBytes = base64Decode(loggedSigContent);
        if (!DerUtils.bytesEqual(loggedSigBytes, expectedSignatureBytes)) {
          errors.add('Rekor entry signature does not match bundle signature');
        }
      }

      final pubKeyObj = sigObj?['publicKey'] as Map<String, dynamic>?;
      final loggedCertPemB64 = pubKeyObj?['content'] as String?;
      if (loggedCertPemB64 != null) {
        final loggedCertPem = utf8.decode(base64Decode(loggedCertPemB64));
        final clean =
            loggedCertPem
                .split('\n')
                .where((l) => !l.startsWith('-----'))
                .join()
                .trim();
        final loggedCertDer = base64Decode(clean);
        if (!DerUtils.bytesEqual(loggedCertDer, signingCert.rawDer)) {
          errors.add(
            'Rekor entry certificate does not match bundle certificate',
          );
        }
      }
    }

    // 2. Find matching Rekor public key from trusted_root.json
    final logIdKeyId = tlogEntryMap['logId']?['keyId'] as String?;
    final tlogs = trustedRootJson['tlogs'] as List?;
    Map<String, dynamic>? matchingTlog;

    if (tlogs != null) {
      for (final t in tlogs) {
        if (t['logId']?['keyId'] == logIdKeyId) {
          matchingTlog = t as Map<String, dynamic>;
          break;
        }
      }
    }

    if (matchingTlog == null) {
      errors.add(
        'No matching Rekor transparency log found in trusted root for logId: $logIdKeyId',
      );
      return RekorVerificationResult(
        isValid: false,
        logIndex: -1,
        integratedTime: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        errors: errors,
      );
    }

    final rekorPubDer = base64Decode(
      matchingTlog['publicKey']['rawBytes'] as String,
    );
    final rekorPubKey = DerUtils.parseSpkiPublicKey(
      rekorPubDer,
      curveName: 'secp256r1',
    );

    final integratedTimeSec =
        int.tryParse(tlogEntryMap['integratedTime']?.toString() ?? '0') ?? 0;
    final integratedTime = DateTime.fromMillisecondsSinceEpoch(
      integratedTimeSec * 1000,
      isUtc: true,
    );

    // 3. Verify Inclusion Proof & Checkpoint if present
    final ip = tlogEntryMap['inclusionProof'] as Map<String, dynamic>?;
    final entryIndex =
        int.tryParse(tlogEntryMap['logIndex']?.toString() ?? '-1') ?? -1;

    if (ip != null) {
      final proofLogIndex = int.parse(ip['logIndex'].toString());
      final treeSize = int.parse(ip['treeSize'].toString());
      final rootHash = base64Decode(ip['rootHash'] as String);
      final proofHashes =
          (ip['hashes'] as List).map((h) => base64Decode(h as String)).toList();

      final leafHash = MerkleVerifier.computeLeafHash(canonBodyBytes);
      final inclusionOk = MerkleVerifier.verifyInclusion(
        logIndex: proofLogIndex,
        treeSize: treeSize,
        leafHash: leafHash,
        proofHashes: proofHashes,
        rootHash: rootHash,
      );

      if (!inclusionOk) {
        errors.add('Merkle inclusion proof verification failed');
      }

      // Checkpoint note verification
      final checkpointObj = ip['checkpoint'] as Map<String, dynamic>?;
      final checkpointEnv = checkpointObj?['envelope'] as String?;
      if (checkpointEnv != null) {
        final noteEndIdx = checkpointEnv.indexOf('\n\n');
        if (noteEndIdx == -1) {
          errors.add(
            'Malformed checkpoint envelope (missing blank line separator)',
          );
        } else {
          final noteText = checkpointEnv.substring(0, noteEndIdx + 1);
          final lines = checkpointEnv.split('\n');
          final sigLine = lines.firstWhere(
            (l) => l.startsWith('— ') || l.startsWith('\u2014 '),
            orElse: () => '',
          );
          if (sigLine.isEmpty) {
            errors.add('Missing signature line in checkpoint note');
          } else {
            final sigParts = sigLine.split(' ');
            final sigB64 = sigParts.length > 2 ? sigParts[2] : '';
            final rawSigBytes = base64Decode(sigB64);
            final derSigBytes =
                rawSigBytes.length > 4 ? rawSigBytes.sublist(4) : rawSigBytes;
            final cpSig = DerUtils.parseDerSignature(derSigBytes);

            final noteDigest = Uint8List.fromList(
              crypto.sha256.convert(utf8.encode(noteText)).bytes,
            );
            final cpSigOk = EcdsaVerifier.verify(
              hash: noteDigest,
              signature: cpSig,
              publicKey: rekorPubKey,
            );
            if (!cpSigOk) {
              errors.add('Rekor checkpoint signature verification failed');
            }
          }
        }
      }
    }

    // 4. Verify Inclusion Promise (Signed Entry Timestamp) if present
    final inclusionPromise =
        tlogEntryMap['inclusionPromise'] as Map<String, dynamic>?;
    if (inclusionPromise != null) {
      final setSigB64 = inclusionPromise['signedEntryTimestamp'] as String?;
      if (setSigB64 != null) {
        final setSig = DerUtils.parseDerSignature(base64Decode(setSigB64));
        final keyIdBytes = base64Decode(logIdKeyId!);
        final logIdHex = DerUtils.hexEncode(keyIdBytes);

        // RFC 8785 canonical JSON
        final setPayload = jsonEncode({
          'body': canonBodyB64,
          'integratedTime': integratedTimeSec,
          'logID': logIdHex,
          'logIndex': entryIndex,
        });

        final setPayloadHash = Uint8List.fromList(
          crypto.sha256.convert(utf8.encode(setPayload)).bytes,
        );

        final setOk = EcdsaVerifier.verify(
          hash: setPayloadHash,
          signature: setSig,
          publicKey: rekorPubKey,
        );
        if (!setOk) {
          errors.add('Rekor SET signature verification failed');
        }
      }
    }

    return RekorVerificationResult(
      isValid: errors.isEmpty,
      logIndex: entryIndex,
      integratedTime: integratedTime,
      errors: errors,
    );
  }
}
