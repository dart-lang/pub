// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

/// Lightweight ASN.1 parser for X.509 certificates and Sigstore extensions.
class Asn1Reader {
  final Uint8List bytes;
  int offset = 0;

  Asn1Reader(this.bytes, [this.offset = 0]);

  bool get hasNext => offset < bytes.length;

  int readTag() {
    if (offset >= bytes.length) return -1;
    return bytes[offset++];
  }

  int readLength() {
    final first = bytes[offset++];
    if ((first & 0x80) == 0) {
      return first;
    }
    final numOctets = first & 0x7F;
    var length = 0;
    for (var i = 0; i < numOctets; i++) {
      length = (length << 8) | bytes[offset++];
    }
    return length;
  }

  Uint8List readBytes(int length) {
    final slice = bytes.sublist(offset, offset + length);
    offset += length;
    return slice;
  }

  /// Parses Sigstore OID extensions from X.509 certificate DER bytes.
  static FulcioCertificateInfo parseFulcioCertificate(Uint8List derBytes) {
    String? issuer;
    String? repoUri;
    String? repoRef;
    String? workflowPath;
    String? jobWorkflowSha;
    String? runnerEnvironment;
    String? sanUri;

    // OID 1.3.6.1.4.1.57264.1.x: 2B 06 01 04 01 83 BF 30 01 <x>
    final sigstorePrefix = [
      0x2B,
      0x06,
      0x01,
      0x04,
      0x01,
      0x83,
      0xBF,
      0x30,
      0x01,
    ];

    for (var i = 0; i < derBytes.length - sigstorePrefix.length - 2; i++) {
      var match = true;
      for (var j = 0; j < sigstorePrefix.length; j++) {
        if (derBytes[i + j] != sigstorePrefix[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        final subOid = derBytes[i + sigstorePrefix.length];
        final value = _extractNearbyUtf8String(
          derBytes,
          i + sigstorePrefix.length + 1,
        );
        if (value != null) {
          switch (subOid) {
            case 0x01: // Issuer
              issuer ??= value;
              break;
            case 0x05: // Source Repository URI
              repoUri ??= value;
              break;
            case 0x06: // Source Repository Ref
              repoRef ??= value;
              break;
            case 0x0A: // Runner Environment
              runnerEnvironment ??= value;
              break;
            case 0x12: // Workflow Path
              workflowPath ??= value;
              break;
            case 0x13: // Job Workflow SHA
              jobWorkflowSha ??= value;
              break;
          }
        }
      }
    }

    // Search for SAN URI (e.g. https://github.com/...)
    final sanMatch = RegExp(
      r'https://github\.com/[^\x00-\x1F\x7F-\xFF]+',
    ).firstMatch(utf8.decode(derBytes, allowMalformed: true));
    if (sanMatch != null) {
      sanUri = sanMatch.group(0);
    }

    return FulcioCertificateInfo(
      issuer: issuer,
      sourceRepositoryUri: repoUri,
      sourceRepositoryRef: repoRef,
      workflowPath: workflowPath,
      jobWorkflowSha: jobWorkflowSha,
      runnerEnvironment: runnerEnvironment,
      sanUri: sanUri,
    );
  }

  static String? _extractNearbyUtf8String(Uint8List bytes, int startIndex) {
    final searchLimit = (startIndex + 20).clamp(0, bytes.length);
    for (var idx = startIndex; idx < searchLimit; idx++) {
      final tag = bytes[idx];
      // UTF8String (0x0C), PrintableString (0x13), IA5String (0x16),
      // or OctetString (0x04).
      if (tag == 0x0C || tag == 0x13 || tag == 0x16 || tag == 0x04) {
        if (idx + 1 >= bytes.length) continue;
        final len = bytes[idx + 1];
        if (idx + 2 + len <= bytes.length && len > 0) {
          final strBytes = bytes.sublist(idx + 2, idx + 2 + len);
          final text = utf8.decode(strBytes, allowMalformed: true);
          if (text.isNotEmpty && !text.contains('\x00')) {
            return text;
          }
        }
      }
    }
    return null;
  }
}
