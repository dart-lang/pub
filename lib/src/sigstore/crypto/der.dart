// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'asn1.dart';
import 'ec.dart';

/// Utilities for parsing DER-encoded ASN.1 cryptographic structures.
final class DerUtils {
  DerUtils._();

  /// Parses an ASN.1 DER-encoded ECDSA signature into [EcSignature].
  ///
  /// The input [derBytes] must be a DER SEQUENCE containing two INTEGERs (r and s).
  ///
  /// Throws a [FormatException] if [derBytes] is not a valid DER ECDSA signature.
  ///
  /// It is an error if [derBytes] is empty.
  ///
  /// Performance is O(n) where n is the length of [derBytes].
  static EcSignature parseDerSignature(Uint8List derBytes) {
    ArgumentError.checkNotNull(derBytes, 'derBytes');
    if (derBytes.isEmpty) {
      throw ArgumentError.value(derBytes, 'derBytes', 'Must not be empty.');
    }
    try {
      final (seq, _) = Asn1DerReader.readElement(derBytes);
      if (seq.tag != Asn1Tags.sequence || seq.children.length < 2) {
        throw const FormatException(
          'Expected ASN.1 Sequence with at least 2 elements.',
        );
      }
      final r = seq.children[0].toBigInt();
      final s = seq.children[1].toBigInt();
      return EcSignature(r, s);
    } on Exception catch (e) {
      if (e is FormatException || e is ArgumentError) rethrow;
      throw FormatException('Failed to parse DER signature: $e');
    }
  }

  /// Parses a SubjectPublicKeyInfo DER byte sequence into an [EcPublicKey].
  ///
  /// If [curveName] is omitted, determines the curve from the algorithm identifier
  /// OID (defaults to `secp256r1` for 1.2.840.10045.3.1.7 and `secp384r1` for 1.3.132.0.34).
  ///
  /// Throws a [FormatException] if [spkiDer] does not represent a supported EC public key.
  ///
  /// It is an error if [spkiDer] is empty.
  static EcPublicKey parseSpkiPublicKey(
    Uint8List spkiDer, {
    String? curveName,
  }) {
    ArgumentError.checkNotNull(spkiDer, 'spkiDer');
    if (spkiDer.isEmpty) {
      throw ArgumentError.value(spkiDer, 'spkiDer', 'Must not be empty.');
    }
    try {
      final (seq, _) = Asn1DerReader.readElement(spkiDer);
      if (seq.tag != Asn1Tags.sequence || seq.children.length < 2) {
        throw const FormatException('Invalid SubjectPublicKeyInfo structure.');
      }

      var detectedCurve = curveName ?? 'secp256r1';
      final algoSeq = seq.children[0];
      if (curveName == null && algoSeq.children.length > 1) {
        final curveOid = algoSeq.children[1].toOid();
        if (curveOid == '1.3.132.0.34') {
          detectedCurve = 'secp384r1';
        } else if (curveOid == '1.2.840.10045.3.1.7') {
          detectedCurve = 'secp256r1';
        }
      }

      final bitString = seq.children[1];
      final pointBytes = bitString.toBitStringBytes();
      final curve = EcCurve.fromNameOrOid(detectedCurve);
      final point = EcAffinePoint.fromUncompressedBytes(pointBytes, curve);
      return EcPublicKey(point, curve);
    } on Exception catch (e) {
      if (e is FormatException || e is ArgumentError) rethrow;
      throw FormatException('Failed to parse SPKI public key: $e');
    }
  }

  /// Parses a PEM-encoded SubjectPublicKeyInfo string into an [EcPublicKey].
  ///
  /// Throws a [FormatException] if [pem] is not valid PEM or does not contain a valid EC key.
  ///
  /// It is an error if [pem] is empty.
  static EcPublicKey parsePemPublicKey(String pem, {String? curveName}) {
    ArgumentError.checkNotNull(pem, 'pem');
    final trimmed = pem.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(pem, 'pem', 'Must not be empty.');
    }
    final clean =
        trimmed.split('\n').where((l) => !l.startsWith('-----')).join().trim();
    final der = base64Decode(clean);
    return parseSpkiPublicKey(der, curveName: curveName);
  }

  /// Decodes a hexadecimal string into [Uint8List].
  ///
  /// Throws a [FormatException] if [hex] has odd length or non-hex characters.
  ///
  /// It is an error if [hex] has an odd number of characters.
  static Uint8List hexDecode(String hex) {
    if (hex.length.isOdd) {
      throw ArgumentError.value(hex, 'hex', 'Must have an even length.');
    }
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Encodes [bytes] into a lowercase hexadecimal string.
  ///
  /// Performance is O(n) where n is [bytes.length].
  static String hexEncode(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Compares two byte lists in constant time where possible.
  ///
  /// Returns `true` if and only if [a] and [b] have identical lengths and byte values.
  static bool bytesEqual(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
