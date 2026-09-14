// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

/// ASN.1 DER tag constants per ITU-T Recommendation X.690.
abstract final class Asn1Tags {
  static const int boolean = 0x01;
  static const int integer = 0x02;
  static const int bitString = 0x03;
  static const int octetString = 0x04;
  static const int nullTag = 0x05;
  static const int objectIdentifier = 0x06;
  static const int utf8String = 0x0C;
  static const int printableString = 0x13;
  static const int ia5String = 0x16;
  static const int utcTime = 0x17;
  static const int generalizedTime = 0x18;
  static const int sequence = 0x30;
  static const int set = 0x31;
}

/// A parsed ASN.1 DER element.
final class Asn1DerElement {
  /// The ASN.1 tag identifier byte.
  final int tag;

  /// The raw DER-encoded bytes representing this entire element (tag, length, and value).
  final Uint8List rawBytes;

  /// The raw value payload bytes excluding tag and length headers.
  final Uint8List content;

  /// Nested child elements if this element is a constructed type (e.g. SEQUENCE, SET, or context-specific).
  final List<Asn1DerElement> children;

  /// Creates a new [Asn1DerElement].
  Asn1DerElement({
    required this.tag,
    required this.rawBytes,
    required this.content,
    this.children = const [],
  });

  /// Whether this element represents a constructed container (e.g. SEQUENCE or context-specific).
  bool get isConstructed => (tag & 0x20) != 0;

  /// Decodes this INTEGER element into a signed [BigInt].
  ///
  /// Throws a [FormatException] if this element is not an INTEGER.
  BigInt toBigInt() {
    if (tag != Asn1Tags.integer) {
      throw FormatException(
        'Expected tag 0x02 (INTEGER), got 0x${tag.toRadixString(16)}',
      );
    }
    if (content.isEmpty) return BigInt.zero;

    final isNegative = (content[0] & 0x80) != 0;
    var result = BigInt.zero;
    for (final b in content) {
      result = (result << 8) | BigInt.from(b);
    }
    if (!isNegative) {
      return result;
    }
    final mask = (BigInt.one << (content.length * 8)) - BigInt.one;
    return -((~result & mask) + BigInt.one);
  }

  /// Decodes this BIT STRING element into its raw byte payload, stripping the leading unused-bits byte.
  ///
  /// Throws a [FormatException] if this element is not a BIT STRING or is empty.
  Uint8List toBitStringBytes() {
    if (tag != Asn1Tags.bitString) {
      throw FormatException(
        'Expected tag 0x03 (BIT STRING), got 0x${tag.toRadixString(16)}',
      );
    }
    if (content.isEmpty) {
      throw const FormatException('BIT STRING content is empty.');
    }
    // First byte is the number of unused bits in the final byte.
    return Uint8List.sublistView(content, 1);
  }

  /// Decodes this OBJECT IDENTIFIER element into a standard dotted-decimal notation string.
  ///
  /// Throws a [FormatException] if this element is not an OBJECT IDENTIFIER or is malformed.
  String toOid() {
    if (tag != Asn1Tags.objectIdentifier) {
      throw FormatException(
        'Expected tag 0x06 (OBJECT IDENTIFIER), got 0x${tag.toRadixString(16)}',
      );
    }
    if (content.isEmpty) {
      throw const FormatException('Empty OBJECT IDENTIFIER content.');
    }

    final parts = <String>[];
    final b0 = content[0];
    final first = b0 ~/ 40;
    final second = b0 % 40;
    if (first > 2) {
      parts.add('2');
      parts.add((b0 - 80).toString());
    } else {
      parts.add(first.toString());
      parts.add(second.toString());
    }

    var component = BigInt.zero;
    for (var i = 1; i < content.length; i++) {
      final b = content[i];
      component = (component << 7) | BigInt.from(b & 0x7F);
      if ((b & 0x80) == 0) {
        parts.add(component.toString());
        component = BigInt.zero;
      }
    }
    return parts.join('.');
  }

  /// Decodes this UTCTime or GeneralizedTime element into a UTC [DateTime].
  ///
  /// Throws a [FormatException] if this element is not a valid time format.
  DateTime toDateTime() {
    final str = utf8.decode(content, allowMalformed: true);
    if (tag == Asn1Tags.utcTime) {
      // YYMMDDhhmmssZ or YYMMDDhhmmZ
      if (str.length < 10) {
        throw FormatException('Invalid UTCTime string: $str');
      }
      final rawYear = int.parse(str.substring(0, 2));
      final year = rawYear >= 50 ? 1900 + rawYear : 2000 + rawYear;
      final month = int.parse(str.substring(2, 4));
      final day = int.parse(str.substring(4, 6));
      final hour = int.parse(str.substring(6, 8));
      final minute = int.parse(str.substring(8, 10));
      final second =
          (str.length >= 12 && str[10] != 'Z')
              ? int.parse(str.substring(10, 12))
              : 0;
      return DateTime.utc(year, month, day, hour, minute, second);
    } else if (tag == Asn1Tags.generalizedTime) {
      // YYYYMMDDhhmmssZ
      if (str.length < 12) {
        throw FormatException('Invalid GeneralizedTime string: $str');
      }
      final year = int.parse(str.substring(0, 4));
      final month = int.parse(str.substring(4, 6));
      final day = int.parse(str.substring(6, 8));
      final hour = int.parse(str.substring(8, 10));
      final minute = int.parse(str.substring(10, 12));
      final second =
          (str.length >= 14 && str[12] != 'Z')
              ? int.parse(str.substring(12, 14))
              : 0;
      return DateTime.utc(year, month, day, hour, minute, second);
    }
    throw FormatException(
      'Tag 0x${tag.toRadixString(16)} is not a supported time tag.',
    );
  }

  /// Decodes string contents (UTF8String, PrintableString, IA5String, OctetString).
  String toText() {
    return utf8.decode(content, allowMalformed: true);
  }
}

/// Zero-dependency parser for ASN.1 DER binary streams.
final class Asn1DerReader {
  Asn1DerReader._();

  /// Reads a single [Asn1DerElement] from [bytes] at [offset].
  ///
  /// Throws a [FormatException] if [bytes] is truncated or has invalid DER length encoding.
  ///
  /// It is an error if [offset] is negative or exceeds [bytes.length].
  ///
  /// Performance is O(n) where n is the element length in bytes.
  static (Asn1DerElement element, int bytesRead) readElement(
    Uint8List bytes, [
    int offset = 0,
  ]) {
    ArgumentError.checkNotNull(bytes, 'bytes');
    if (offset < 0 || offset >= bytes.length) {
      throw ArgumentError.value(offset, 'offset', 'Offset out of bounds.');
    }

    final start = offset;
    final tag = bytes[offset++];
    if (offset >= bytes.length) {
      throw const FormatException('Unexpected end of DER stream after tag.');
    }

    final lengthByte = bytes[offset++];
    int length;
    if ((lengthByte & 0x80) == 0) {
      length = lengthByte;
    } else {
      final numBytes = lengthByte & 0x7F;
      if (numBytes == 0 || numBytes > 4) {
        throw FormatException(
          'Unsupported indefinite or long length: $numBytes bytes.',
        );
      }
      if (offset + numBytes > bytes.length) {
        throw const FormatException(
          'Unexpected end of DER stream while reading length.',
        );
      }
      length = 0;
      for (var i = 0; i < numBytes; i++) {
        length = (length << 8) | bytes[offset++];
      }
    }

    if (offset + length > bytes.length) {
      throw FormatException(
        'DER content length ($length) overflows available bytes (${bytes.length - offset}).',
      );
    }

    final content = Uint8List.sublistView(bytes, offset, offset + length);
    final rawBytes = Uint8List.sublistView(bytes, start, offset + length);

    final isConstructed = (tag & 0x20) != 0;
    final children = <Asn1DerElement>[];

    if (isConstructed) {
      var childOffset = 0;
      while (childOffset < content.length) {
        final (child, childBytesRead) = readElement(content, childOffset);
        children.add(child);
        childOffset += childBytesRead;
      }
    }

    return (
      Asn1DerElement(
        tag: tag,
        rawBytes: rawBytes,
        content: content,
        children: children,
      ),
      rawBytes.length,
    );
  }

  /// Parses a DER sequence or constructed stream into its child elements.
  ///
  /// Throws a [FormatException] if [bytes] does not begin with an ASN.1 SEQUENCE.
  ///
  /// It is an error if [bytes] is empty.
  static List<Asn1DerElement> readSequence(Uint8List bytes) {
    ArgumentError.checkNotNull(bytes, 'bytes');
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Bytes must not be empty.');
    }
    final (elem, _) = readElement(bytes);
    return elem.children;
  }
}
