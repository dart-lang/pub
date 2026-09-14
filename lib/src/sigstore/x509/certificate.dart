// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../crypto/asn1.dart';
import '../crypto/der.dart';
import '../crypto/ec.dart';
import '../crypto/ecdsa.dart';

/// Represents an X.509 certificate (leaf or CA) used in Sigstore/Fulcio.
final class FulcioCertificate {
  /// The raw DER-encoded certificate bytes.
  final Uint8List rawDer;

  /// The raw DER-encoded TBSCertificate bytes.
  final Uint8List tbsBytes;

  /// The signature bytes on this certificate.
  final Uint8List signatureBytes;

  /// The signature algorithm OID (e.g. `1.2.840.10045.4.3.3` for ecdsa-with-SHA384).
  final String sigAlgoOid;

  /// The public key extracted from the certificate.
  final EcPublicKey publicKey;

  /// The elliptic curve name of [publicKey] (e.g. `secp256r1` or `secp384r1`).
  final String curveName;

  /// Certificate start validity timestamp in UTC.
  final DateTime notBefore;

  /// Certificate expiration timestamp in UTC.
  final DateTime notAfter;

  /// OIDC issuer extension value (OID `1.3.6.1.4.1.57264.1.1` or `1.3.6.1.4.1.57264.1.8`).
  final String? oidcIssuer;

  /// Repository extension value (OID `1.3.6.1.4.1.57264.1.5` or `1.3.6.1.4.1.57264.1.12`).
  final String? repository;

  /// Git ref extension value (OID `1.3.6.1.4.1.57264.1.6` or `1.3.6.1.4.1.57264.1.14`).
  final String? gitRef;

  /// Subject Alternative Name URI extension value (OID `2.5.29.17`).
  final String? sanUri;

  /// All parsed extension OIDs mapped to their string or raw string values.
  final Map<String, String> extensions;

  FulcioCertificate({
    required this.rawDer,
    required this.tbsBytes,
    required this.signatureBytes,
    required this.sigAlgoOid,
    required this.publicKey,
    required this.curveName,
    required this.notBefore,
    required this.notAfter,
    this.oidcIssuer,
    this.repository,
    this.gitRef,
    this.sanUri,
    this.extensions = const {},
  });

  /// Parses a DER-encoded X.509 certificate.
  ///
  /// Throws a [FormatException] if [der] is malformed or missing required X.509 structures.
  ///
  /// It is an error if [der] is empty.
  static FulcioCertificate fromDer(Uint8List der) {
    ArgumentError.checkNotNull(der, 'der');
    if (der.isEmpty) {
      throw ArgumentError.value(
        der,
        'der',
        'Certificate DER bytes must not be empty.',
      );
    }

    try {
      final (certSeq, _) = Asn1DerReader.readElement(der);
      if (certSeq.tag != Asn1Tags.sequence || certSeq.children.length < 3) {
        throw const FormatException(
          'Expected X.509 certificate sequence with at least 3 elements.',
        );
      }

      final tbsObj = certSeq.children[0];
      final tbsBytes = tbsObj.rawBytes;
      if (tbsObj.tag != Asn1Tags.sequence) {
        throw const FormatException('Expected TBSCertificate sequence.');
      }

      var idx = 0;
      if (tbsObj.children[0].tag == 0xA0) {
        idx++; // Skip version [0]
      }
      idx++; // Skip serialNumber
      idx++; // Skip signature algo
      idx++; // Skip issuer

      final validitySeq = tbsObj.children[idx++];
      final notBefore = validitySeq.children[0].toDateTime();
      final notAfter = validitySeq.children[1].toDateTime();

      idx++; // Skip subject

      final spkiSeq = tbsObj.children[idx++];
      final spkiAlgoSeq = spkiSeq.children[0];
      var detectedCurve = 'secp256r1';
      if (spkiAlgoSeq.children.length > 1) {
        final curveOid = spkiAlgoSeq.children[1].toOid();
        if (curveOid == '1.3.132.0.34') {
          detectedCurve = 'secp384r1';
        } else if (curveOid == '1.2.840.10045.3.1.7') {
          detectedCurve = 'secp256r1';
        }
      }

      final pubKeyBits = spkiSeq.children[1].toBitStringBytes();
      final curve = EcCurve.fromNameOrOid(detectedCurve);
      final point = EcAffinePoint.fromUncompressedBytes(pubKeyBits, curve);
      final pubKey = EcPublicKey(point, curve);

      // Search for extensions [3] (tag 0xA3)
      final parsedExts = <String, String>{};
      String? issuerExt;
      String? repoExt;
      String? gitRefExt;
      String? sanUriExt;

      for (var i = idx; i < tbsObj.children.length; i++) {
        final elem = tbsObj.children[i];
        if (elem.tag == 0xA3) {
          final (extSeqObj, _) = Asn1DerReader.readElement(elem.content);
          if (extSeqObj.tag == Asn1Tags.sequence) {
            for (final extElem in extSeqObj.children) {
              if (extElem.tag != Asn1Tags.sequence ||
                  extElem.children.length < 2) {
                continue;
              }
              final oid = extElem.children[0].toOid();
              final octetString = extElem.children.last;

              final value = _extractStringFromExtension(octetString.content);
              parsedExts[oid] = value;

              if (oid == '1.3.6.1.4.1.57264.1.1' ||
                  oid == '1.3.6.1.4.1.57264.1.8') {
                issuerExt ??= value;
              } else if (oid == '1.3.6.1.4.1.57264.1.5' ||
                  oid == '1.3.6.1.4.1.57264.1.12') {
                repoExt ??= value;
              } else if (oid == '1.3.6.1.4.1.57264.1.6' ||
                  oid == '1.3.6.1.4.1.57264.1.14') {
                gitRefExt ??= value;
              } else if (oid == '2.5.29.17') {
                sanUriExt = _extractSanUri(octetString.content) ?? value;
              }
            }
          }
        }
      }

      final sigSeq = certSeq.children[1];
      final sigAlgoOid = sigSeq.children[0].toOid();

      final sigBitString = certSeq.children[2];
      final signatureBytes = sigBitString.toBitStringBytes();

      return FulcioCertificate(
        rawDer: der,
        tbsBytes: tbsBytes,
        signatureBytes: signatureBytes,
        sigAlgoOid: sigAlgoOid,
        publicKey: pubKey,
        curveName: detectedCurve,
        notBefore: notBefore,
        notAfter: notAfter,
        oidcIssuer: issuerExt,
        repository: repoExt,
        gitRef: gitRefExt,
        sanUri: sanUriExt,
        extensions: parsedExts,
      );
    } on Exception catch (e) {
      if (e is FormatException || e is ArgumentError) rethrow;
      throw FormatException('Failed to parse X.509 certificate: $e');
    }
  }

  /// Verifies that this certificate was signed by [issuerCert].
  ///
  /// Computes the cryptographic digest over [tbsBytes] using the digest algorithm
  /// specified by [sigAlgoOid] (SHA-384 or SHA-256) and verifies the ECDSA signature
  /// with [issuerCert.publicKey].
  ///
  /// Returns `true` if the signature is mathematically valid.
  bool verifySignedBy(FulcioCertificate issuerCert) {
    ArgumentError.checkNotNull(issuerCert, 'issuerCert');

    Uint8List digestBytes;
    if (sigAlgoOid == '1.2.840.10045.4.3.3') {
      digestBytes = Uint8List.fromList(sha384.convert(tbsBytes).bytes);
    } else {
      digestBytes = Uint8List.fromList(sha256.convert(tbsBytes).bytes);
    }

    final ecSig = DerUtils.parseDerSignature(signatureBytes);
    return EcdsaVerifier.verify(
      hash: digestBytes,
      signature: ecSig,
      publicKey: issuerCert.publicKey,
    );
  }

  /// Checks whether [time] falls between [notBefore] and [notAfter].
  bool isWithinValidity(DateTime time) {
    return !time.isBefore(notBefore) && !time.isAfter(notAfter);
  }

  static String _extractStringFromExtension(Uint8List valueBytes) {
    try {
      final (obj, _) = Asn1DerReader.readElement(valueBytes);
      return obj.toText();
    } catch (_) {
      return utf8.decode(valueBytes, allowMalformed: true);
    }
  }

  static String? _extractSanUri(Uint8List valueBytes) {
    try {
      final (seq, _) = Asn1DerReader.readElement(valueBytes);
      if (seq.tag == Asn1Tags.sequence) {
        for (final elem in seq.children) {
          // GeneralName: tag 0x86 = [6] URI
          if (elem.tag == 0x86) {
            return utf8.decode(elem.content, allowMalformed: true);
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
