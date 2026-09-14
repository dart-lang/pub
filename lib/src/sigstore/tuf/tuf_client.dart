import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../crypto/der.dart';
import '../crypto/ecdsa.dart';

/// Client for fetching and cryptographically verifying TUF (The Update Framework)
/// metadata from the Sigstore TUF mirror.
final class TufClient {
  /// Default Sigstore CDN TUF repository URL.
  static const String defaultMirrorUrl = 'https://tuf-repo-cdn.sigstore.dev';

  final http.Client _httpClient;
  final String _mirrorUrl;

  TufClient({http.Client? httpClient, String mirrorUrl = defaultMirrorUrl})
    : _httpClient = httpClient ?? http.Client(),
      _mirrorUrl = mirrorUrl.replaceAll(RegExp(r'/+$'), '');

  /// Encodes [obj] into OLPC Canonical JSON format required by TUF.
  ///
  /// See: http://wiki.laptop.org/go/Canonical_JSON
  ///
  /// Performance is O(n) where n is the number of nodes in [obj].
  static String olpcCanonicalJson(dynamic obj) {
    final buffer = StringBuffer();
    void encode(dynamic val) {
      if (val == null) {
        buffer.write('null');
      } else if (val is bool) {
        buffer.write(val ? 'true' : 'false');
      } else if (val is int) {
        buffer.write(val.toString());
      } else if (val is String) {
        final escaped = val.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        buffer.write('"$escaped"');
      } else if (val is List) {
        buffer.write('[');
        for (var i = 0; i < val.length; i++) {
          if (i > 0) buffer.write(',');
          encode(val[i]);
        }
        buffer.write(']');
      } else if (val is Map) {
        buffer.write('{');
        final sortedKeys = val.keys.map((k) => k.toString()).toList()..sort();
        for (var i = 0; i < sortedKeys.length; i++) {
          if (i > 0) buffer.write(',');
          final k = sortedKeys[i];
          final escapedK = k.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
          buffer.write('"$escapedK":');
          encode(val[k]);
        }
        buffer.write('}');
      } else {
        throw ArgumentError(
          'Unsupported type in canonical JSON: ${val.runtimeType}',
        );
      }
    }

    encode(obj);
    return buffer.toString();
  }

  /// Verifies the threshold signatures for a TUF [metadata] payload using the role definition
  /// [roleDef] and available public [keys].
  ///
  /// Returns `true` if and only if at least `threshold` valid signatures are present.
  static bool verifyRoleSignatures({
    required Map<String, dynamic> metadata,
    required Map<String, dynamic> roleDef,
    required Map<String, dynamic> keys,
  }) {
    final signedObj = metadata['signed'] as Map<String, dynamic>;
    final canonJson = olpcCanonicalJson(signedObj);
    final digest = Uint8List.fromList(
      crypto.sha256.convert(utf8.encode(canonJson)).bytes,
    );

    final threshold = roleDef['threshold'] as int;
    final allowedKeyids = List<String>.from(roleDef['keyids'] as List);
    final signatures = metadata['signatures'] as List;

    var validCount = 0;
    final verifiedKeys = <String>{};

    for (final sigObj in signatures) {
      final keyid = sigObj['keyid'] as String;
      if (!allowedKeyids.contains(keyid) || verifiedKeys.contains(keyid)) {
        continue;
      }
      final keyInfo = keys[keyid] as Map<String, dynamic>?;
      if (keyInfo == null) continue;

      final sigHex = sigObj['sig'] as String;
      final sigDer = DerUtils.hexDecode(sigHex);
      final ecSig = DerUtils.parseDerSignature(sigDer);
      final pubPem = keyInfo['keyval']['public'] as String;
      final pubKey = DerUtils.parsePemPublicKey(pubPem, curveName: 'secp256r1');

      final ok = EcdsaVerifier.verify(
        hash: digest,
        signature: ecSig,
        publicKey: pubKey,
      );
      if (ok) {
        verifiedKeys.add(keyid);
        validCount++;
      }
    }
    return validCount >= threshold;
  }

  /// Refreshes the trusted root from the TUF mirror and returns the verified `trusted_root.json` string.
  ///
  /// Throws a [StateError] if any metadata in the TUF hierarchy fails verification.
  /// Throws an [http.ClientException] on network failure.
  Future<String> refreshTrustedRoot({int initialRootVersion = 1}) async {
    // 1. Root update loop: step forward from initialRootVersion until 404
    var currentVersion = initialRootVersion;
    Map<String, dynamic>? currentRoot;

    while (true) {
      final nextVersion = currentVersion;
      final uri = Uri.parse('$_mirrorUrl/$nextVersion.root.json');
      final res = await _httpClient.get(uri);
      if (res.statusCode == 200) {
        final rootJson = jsonDecode(res.body) as Map<String, dynamic>;
        final signed = rootJson['signed'] as Map<String, dynamic>;
        final roles = signed['roles'] as Map<String, dynamic>;
        final keys = signed['keys'] as Map<String, dynamic>;

        final ok = verifyRoleSignatures(
          metadata: rootJson,
          roleDef: roles['root'] as Map<String, dynamic>,
          keys: keys,
        );
        if (!ok) {
          throw StateError(
            'TUF root.json version $nextVersion failed signature verification.',
          );
        }
        currentRoot = rootJson;
        currentVersion++;
      } else if (res.statusCode == 404) {
        if (currentRoot == null) {
          throw StateError(
            'Failed to fetch initial root version $initialRootVersion.',
          );
        }
        break;
      } else {
        throw StateError('Unexpected HTTP ${res.statusCode} fetching $uri');
      }
    }

    final rootSigned = currentRoot['signed'] as Map<String, dynamic>;
    final roles = rootSigned['roles'] as Map<String, dynamic>;
    final rootKeys = rootSigned['keys'] as Map<String, dynamic>;

    // 2. Fetch and verify timestamp.json
    final tsUri = Uri.parse('$_mirrorUrl/timestamp.json');
    final tsRes = await _httpClient.get(tsUri);
    if (tsRes.statusCode != 200) {
      throw StateError(
        'Failed to fetch timestamp.json: HTTP ${tsRes.statusCode}',
      );
    }
    final timestamp = jsonDecode(tsRes.body) as Map<String, dynamic>;
    if (!verifyRoleSignatures(
      metadata: timestamp,
      roleDef: roles['timestamp'] as Map<String, dynamic>,
      keys: rootKeys,
    )) {
      throw StateError('timestamp.json signature verification failed.');
    }

    final tsMeta = timestamp['signed']['meta'] as Map<String, dynamic>;
    final snapshotVersion = tsMeta['snapshot.json']['version'] as int;

    // 3. Fetch and verify snapshot.json
    final snapUri = Uri.parse('$_mirrorUrl/$snapshotVersion.snapshot.json');
    final snapRes = await _httpClient.get(snapUri);
    if (snapRes.statusCode != 200) {
      throw StateError(
        'Failed to fetch snapshot.json: HTTP ${snapRes.statusCode}',
      );
    }
    final snapshot = jsonDecode(snapRes.body) as Map<String, dynamic>;
    if (!verifyRoleSignatures(
      metadata: snapshot,
      roleDef: roles['snapshot'] as Map<String, dynamic>,
      keys: rootKeys,
    )) {
      throw StateError('snapshot.json signature verification failed.');
    }

    final snapMeta = snapshot['signed']['meta'] as Map<String, dynamic>;
    final targetsVersion = snapMeta['targets.json']['version'] as int;

    // 4. Fetch and verify targets.json
    final targetsUri = Uri.parse('$_mirrorUrl/$targetsVersion.targets.json');
    final targetsRes = await _httpClient.get(targetsUri);
    if (targetsRes.statusCode != 200) {
      throw StateError(
        'Failed to fetch targets.json: HTTP ${targetsRes.statusCode}',
      );
    }
    final targets = jsonDecode(targetsRes.body) as Map<String, dynamic>;
    if (!verifyRoleSignatures(
      metadata: targets,
      roleDef: roles['targets'] as Map<String, dynamic>,
      keys: rootKeys,
    )) {
      throw StateError('targets.json signature verification failed.');
    }

    // 5. Look up trusted_root.json target
    final targetsMeta = targets['signed']['targets'] as Map<String, dynamic>;
    final trTarget = targetsMeta['trusted_root.json'] as Map<String, dynamic>?;
    if (trTarget == null) {
      throw StateError('trusted_root.json target not found in targets.json.');
    }
    final expectedHash = trTarget['hashes']['sha256'] as String;
    final expectedLength = trTarget['length'] as int;

    // 6. Fetch target trusted_root.json
    final targetUri = Uri.parse(
      '$_mirrorUrl/targets/$expectedHash.trusted_root.json',
    );
    var trRes = await _httpClient.get(targetUri);
    if (trRes.statusCode != 200) {
      // Fall back to un-prefixed target name
      trRes = await _httpClient.get(
        Uri.parse('$_mirrorUrl/targets/trusted_root.json'),
      );
    }
    if (trRes.statusCode != 200) {
      throw StateError(
        'Failed to fetch target trusted_root.json: HTTP ${trRes.statusCode}',
      );
    }

    final targetBytes = trRes.bodyBytes;
    if (targetBytes.length != expectedLength) {
      throw StateError(
        'Length mismatch for trusted_root.json: expected $expectedLength, got ${targetBytes.length}',
      );
    }
    final actualHash = crypto.sha256.convert(targetBytes).toString();
    if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
      throw StateError(
        'SHA-256 mismatch for trusted_root.json: expected $expectedHash, got $actualHash',
      );
    }

    return trRes.body;
  }
}
