import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Utilities for In-toto DSSE (Dead Simple Signing Envelope) verification.
///
/// See the DSSE specification: https://github.com/secure-systems-lab/dsse
final class DsseEnvelope {
  DsseEnvelope._();

  /// Formats the Pre-Authentication Encoding (PAE) for DSSE v1:
  /// `PAE(payloadType, payload) = "DSSEv1" + " " + len(payloadType) + " " + payloadType + " " + len(payload) + " " + payload`
  ///
  /// Performance is O(n) where n is `payloadType.length + payloadBytes.length`.
  ///
  /// It is an error if [payloadType] is empty.
  static Uint8List formatPae(String payloadType, List<int> payloadBytes) {
    ArgumentError.checkNotNull(payloadType, 'payloadType');
    ArgumentError.checkNotNull(payloadBytes, 'payloadBytes');

    if (payloadType.isEmpty) {
      throw ArgumentError.value(
        payloadType,
        'payloadType',
        'Must not be empty.',
      );
    }

    final typeBytes = utf8.encode(payloadType);
    final prefix = utf8.encode('DSSEv1 ${typeBytes.length} ');
    final mid = utf8.encode(' ${payloadBytes.length} ');

    final result = Uint8List(
      prefix.length + typeBytes.length + mid.length + payloadBytes.length,
    );
    var offset = 0;
    result.setAll(offset, prefix);
    offset += prefix.length;
    result.setAll(offset, typeBytes);
    offset += typeBytes.length;
    result.setAll(offset, mid);
    offset += mid.length;
    result.setAll(offset, payloadBytes);
    return result;
  }

  /// Computes the SHA-256 digest of the DSSE Pre-Authentication Encoding (PAE).
  static Uint8List computePaeDigest(
    String payloadType,
    List<int> payloadBytes,
  ) {
    final pae = formatPae(payloadType, payloadBytes);
    return Uint8List.fromList(crypto.sha256.convert(pae).bytes);
  }

  /// Verifies whether an in-toto statement payload contains a subject matching [expectedSha256Hex].
  ///
  /// Supports in-toto statement format v0.1 (`https://in-toto.io/Statement/v0.1`)
  /// and v1.0 (`https://in-toto.io/Statement/v1`).
  ///
  /// Returns `true` if at least one subject in the statement specifies a matching sha256 digest.
  ///
  /// Throws a [FormatException] if [statementJson] is not valid JSON.
  static bool matchesSubjectDigest(
    String statementJson,
    String expectedSha256Hex,
  ) {
    ArgumentError.checkNotNull(statementJson, 'statementJson');
    ArgumentError.checkNotNull(expectedSha256Hex, 'expectedSha256Hex');

    final normalizedExpected = expectedSha256Hex.trim().toLowerCase();
    final decoded = jsonDecode(statementJson) as Map<String, dynamic>;
    final subjects = decoded['subject'] as List?;
    if (subjects == null) return false;

    for (final s in subjects) {
      if (s is Map<String, dynamic>) {
        final digest = s['digest'] as Map<String, dynamic>?;
        final sha256Val = digest?['sha256'] as String?;
        if (sha256Val != null &&
            sha256Val.trim().toLowerCase() == normalizedExpected) {
          return true;
        }
      }
    }
    return false;
  }
}
