import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pub_semver/pub_semver.dart';

import '../crypto/der.dart';
import '../crypto/ecdsa.dart';
import '../dsse/dsse.dart';
import '../rekor/tlog.dart';
import '../x509/certificate.dart';

/// Result of verifying a Sigstore package attestation bundle.
final class AttestationVerificationResult {
  /// Whether verification succeeded completely without any errors.
  final bool isValid;

  /// The name of the verified package.
  final String packageName;

  /// The version of the package, if provided.
  final Version? packageVersion;

  /// The verified source repository (e.g. `https://github.com/owner/repo`).
  final String? repository;

  /// The verified signer identity (SAN URI).
  final String? signerIdentity;

  /// The verified OIDC issuer (e.g. `https://token.actions.githubusercontent.com`).
  final String? oidcIssuer;

  /// List of verification errors if [isValid] is false.
  final List<String> errors;

  AttestationVerificationResult({
    required this.isValid,
    required this.packageName,
    this.packageVersion,
    this.repository,
    this.signerIdentity,
    this.oidcIssuer,
    this.errors = const [],
  });
}

/// Parsed Sigstore bundle representation (v0.2 and v0.3).
final class SigstoreBundle {
  final String mediaType;
  final FulcioCertificate certificate;
  final List<Map<String, dynamic>> tlogEntries;
  final Map<String, dynamic>? messageSignature;
  final Map<String, dynamic>? dsseEnvelope;

  SigstoreBundle({
    required this.mediaType,
    required this.certificate,
    required this.tlogEntries,
    this.messageSignature,
    this.dsseEnvelope,
  });

  bool get isMessageSignature => messageSignature != null;
  bool get isDsseEnvelope => dsseEnvelope != null;

  /// Parses a Sigstore bundle from a JSON string.
  ///
  /// Throws a [FormatException] if the JSON structure is invalid.
  static SigstoreBundle fromJson(String jsonString) {
    ArgumentError.checkNotNull(jsonString, 'jsonString');
    final map = jsonDecode(jsonString) as Map<String, dynamic>;

    final mediaType = map['mediaType'] as String? ?? 'unknown';
    final vm = map['verificationMaterial'] as Map<String, dynamic>?;
    if (vm == null) {
      throw const FormatException(
        'Sigstore bundle missing verificationMaterial',
      );
    }

    final certObj = vm['certificate'] as Map<String, dynamic>?;
    if (certObj == null || certObj['rawBytes'] == null) {
      throw const FormatException('Sigstore bundle missing certificate');
    }
    final certDer = base64Decode(certObj['rawBytes'] as String);
    final cert = FulcioCertificate.fromDer(certDer);

    final tlogList =
        (vm['tlogEntries'] as List? ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();

    return SigstoreBundle(
      mediaType: mediaType,
      certificate: cert,
      tlogEntries: tlogList,
      messageSignature: map['messageSignature'] as Map<String, dynamic>?,
      dsseEnvelope: map['dsseEnvelope'] as Map<String, dynamic>?,
    );
  }
}

/// Pure Dart Sigstore attestation verifier.
final class PureDartSigstoreVerifier {
  PureDartSigstoreVerifier._();

  /// Verifies [archiveBytes] against [bundle] and [trustedRootJson].
  ///
  /// Verifies:
  /// 1. Leaf certificate signature against Fulcio CA chain in [trustedRootJson].
  /// 2. Artifact SHA-256 against message signature or DSSE envelope in-toto statement.
  /// 3. ECDSA signature over artifact digest or DSSE PAE using leaf public key.
  /// 4. Rekor transparency log proofs (inclusion proof + checkpoint note signature + SET).
  /// 5. Leaf certificate validity period covering the log integration time.
  /// 6. Policy checks: OIDC issuer and expected source repository.
  static AttestationVerificationResult verify({
    required String packageName,
    Version? packageVersion,
    required List<int> archiveBytes,
    required SigstoreBundle bundle,
    required Map<String, dynamic> trustedRootJson,
    String? expectedRepository,
    String expectedIssuer = 'https://token.actions.githubusercontent.com',
  }) {
    ArgumentError.checkNotNull(packageName, 'packageName');
    ArgumentError.checkNotNull(archiveBytes, 'archiveBytes');
    ArgumentError.checkNotNull(bundle, 'bundle');
    ArgumentError.checkNotNull(trustedRootJson, 'trustedRootJson');

    final errors = <String>[];
    final archiveHash = Uint8List.fromList(
      crypto.sha256.convert(archiveBytes).bytes,
    );
    final archiveHashHex = DerUtils.hexEncode(archiveHash);

    final leafCert = bundle.certificate;

    // 1. Verify Certificate Chain against trusted root
    final caList = trustedRootJson['certificateAuthorities'] as List? ?? [];
    var chainVerified = false;
    for (final ca in caList) {
      final certChain = ca['certChain']?['certificates'] as List? ?? [];
      if (certChain.isEmpty) continue;

      try {
        final parsedChain =
            certChain.map((c) {
              final der = base64Decode(c['rawBytes'] as String);
              return FulcioCertificate.fromDer(der);
            }).toList();

        if (parsedChain.length >= 2) {
          final intermediate = parsedChain[0];
          final root = parsedChain[1];

          final leafOk = leafCert.verifySignedBy(intermediate);
          final interOk = intermediate.verifySignedBy(root);
          if (leafOk && interOk) {
            chainVerified = true;
            break;
          }
        } else if (parsedChain.length == 1) {
          final root = parsedChain[0];
          if (leafCert.verifySignedBy(root)) {
            chainVerified = true;
            break;
          }
        }
      } catch (_) {}
    }

    if (!chainVerified) {
      errors.add(
        'Fulcio certificate chain verification failed against trusted root',
      );
    }

    // 2. Verify signature on artifact / DSSE envelope
    var expectedSigBytes = Uint8List(0);
    var payloadHashToVerifyInTlog = Uint8List(0);

    if (bundle.isMessageSignature) {
      final ms = bundle.messageSignature!;
      final sigB64 = ms['signature'] as String?;
      final digestB64 = ms['messageDigest']?['digest'] as String?;

      if (sigB64 == null || digestB64 == null) {
        errors.add('Incomplete messageSignature in bundle');
      } else {
        expectedSigBytes = base64Decode(sigB64);
        final declaredDigest = base64Decode(digestB64);

        if (!DerUtils.bytesEqual(declaredDigest, archiveHash)) {
          errors.add(
            'Artifact archive SHA-256 does not match bundle messageDigest',
          );
        }

        final ecSig = DerUtils.parseDerSignature(expectedSigBytes);
        final sigOk = EcdsaVerifier.verify(
          hash: archiveHash,
          signature: ecSig,
          publicKey: leafCert.publicKey,
        );
        if (!sigOk) {
          errors.add(
            'Artifact signature verification failed with leaf public key',
          );
        }
        payloadHashToVerifyInTlog = archiveHash;
      }
    } else if (bundle.isDsseEnvelope) {
      final env = bundle.dsseEnvelope!;
      final payloadType = env['payloadType'] as String? ?? '';
      final payloadB64 = env['payload'] as String? ?? '';
      final sigs = env['signatures'] as List? ?? [];

      if (payloadType.isEmpty || payloadB64.isEmpty || sigs.isEmpty) {
        errors.add('Incomplete dsseEnvelope in bundle');
      } else {
        final payloadBytes = base64Decode(payloadB64);
        final paeDigest = DsseEnvelope.computePaeDigest(
          payloadType,
          payloadBytes,
        );
        payloadHashToVerifyInTlog = paeDigest;

        final sigObj = sigs[0] as Map<String, dynamic>;
        final sigB64 = sigObj['sig'] as String;
        expectedSigBytes = base64Decode(sigB64);

        final ecSig = DerUtils.parseDerSignature(expectedSigBytes);
        final sigOk = EcdsaVerifier.verify(
          hash: paeDigest,
          signature: ecSig,
          publicKey: leafCert.publicKey,
        );
        if (!sigOk) {
          errors.add(
            'DSSE envelope signature verification failed with leaf public key',
          );
        }

        // Verify in-toto statement subject
        final statementJson = utf8.decode(payloadBytes);
        final subjectMatch = DsseEnvelope.matchesSubjectDigest(
          statementJson,
          archiveHashHex,
        );
        if (!subjectMatch) {
          errors.add(
            'In-toto statement subject digest does not match artifact SHA-256 ($archiveHashHex)',
          );
        }
      }
    } else {
      errors.add('Bundle must contain either messageSignature or dsseEnvelope');
    }

    // 3. Verify Rekor Transparency Log Entries
    if (bundle.tlogEntries.isEmpty) {
      errors.add('Bundle contains no transparency log entries');
    } else {
      for (final tlogEntry in bundle.tlogEntries) {
        final tlogResult = RekorVerifier.verifyEntry(
          tlogEntryMap: tlogEntry,
          trustedRootJson: trustedRootJson,
          signingCert: leafCert,
          expectedPayloadHash: payloadHashToVerifyInTlog,
          expectedSignatureBytes: expectedSigBytes,
        );
        if (!tlogResult.isValid) {
          errors.addAll(tlogResult.errors);
        }

        // Verify certificate validity at integration time
        if (!leafCert.isWithinValidity(tlogResult.integratedTime)) {
          errors.add(
            'Leaf certificate was not valid at log integrated time (${tlogResult.integratedTime})',
          );
        }
      }
    }

    // 4. Policy checks: OIDC issuer and repository
    final issuer = leafCert.oidcIssuer;
    if (issuer != expectedIssuer) {
      errors.add(
        'OIDC issuer "$issuer" does not match expected issuer "$expectedIssuer"',
      );
    }

    final identity = leafCert.sanUri ?? '';
    var repo = leafCert.repository;
    if (repo != null && !repo.startsWith('http')) {
      repo = 'https://github.com/$repo';
    }
    if (repo == null && identity.startsWith('https://github.com/')) {
      final parts = identity.substring('https://github.com/'.length).split('/');
      if (parts.length >= 2) {
        repo = 'https://github.com/${parts[0]}/${parts[1]}';
      }
    }

    if (expectedRepository != null && expectedRepository.isNotEmpty) {
      if (!expectedRepository.contains('github.com')) {
        errors.add(
          'Package attestation verification is currently only supported for GitHub repositories (got: "$expectedRepository")',
        );
      } else if (repo == null ||
          !_repositoriesMatch(repo, expectedRepository)) {
        errors.add(
          'Attestation identity "$identity" / repository "$repo" does not match expected repository "$expectedRepository"',
        );
      }
    }

    return AttestationVerificationResult(
      isValid: errors.isEmpty,
      packageName: packageName,
      packageVersion: packageVersion,
      repository: repo,
      signerIdentity: identity,
      oidcIssuer: issuer,
      errors: errors,
    );
  }

  static bool _repositoriesMatch(String a, String b) {
    final normA = a
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\.git$'), '')
        .replaceAll(RegExp(r'/+$'), '');
    final normB = b
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\.git$'), '')
        .replaceAll(RegExp(r'/+$'), '');
    return normA == normB || normA.endsWith(normB) || normB.endsWith(normA);
  }
}
