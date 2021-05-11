import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'exception.dart';
import 'format.dart';
import 'utils.dart';

/// Header of a tar entry
///
/// A tar header stores meta-information about the matching tar entry, such as
/// its name.
@sealed
abstract class TarHeader {
  /// Type of header entry. In the V7 TAR format, this field was known as the
  /// link flag.
  TypeFlag get typeFlag;

  /// Name of file or directory entry.
  String get name;

  /// Target name of link (valid for hard links or symbolic links).
  String? get linkName;

  /// Permission and mode bits.
  int get mode;

  /// User ID of owner.
  int get userId;

  /// Group ID of owner.
  int get groupId;

  /// User name of owner.
  String? get userName;

  /// Group name of owner.
  String? get groupName;

  /// Logical file size in bytes.
  int get size;

  /// The time of the last change to the data of the TAR file.
  DateTime get modified;

  /// The time of the last access to the data of the TAR file.
  DateTime? get accessed;

  /// The time of the last change to the data or metadata of the TAR file.
  DateTime? get changed;

  /// Major device number
  int get devMajor;

  /// Minor device number
  int get devMinor;

  /// The TAR format of the header.
  TarFormat get format;

  /// Checks if this header indicates that the file will have content.
  bool get hasContent {
    switch (typeFlag) {
      case TypeFlag.link:
      case TypeFlag.symlink:
      case TypeFlag.block:
      case TypeFlag.dir:
      case TypeFlag.char:
      case TypeFlag.fifo:
        return false;
      default:
        return true;
    }
  }

  /// Creates a tar header from the individual field.
  factory TarHeader({
    required String name,
    TarFormat? format,
    TypeFlag? typeFlag,
    DateTime? modified,
    String? linkName,
    int mode = 0,
    int size = -1,
    String? userName,
    int userId = 0,
    int groupId = 0,
    String? groupName,
    DateTime? accessed,
    DateTime? changed,
    int devMajor = 0,
    int devMinor = 0,
  }) {
    return HeaderImpl.internal(
      name: name,
      modified: modified ?? DateTime.fromMillisecondsSinceEpoch(0),
      format: format ?? TarFormat.pax,
      typeFlag: typeFlag ?? TypeFlag.reg,
      linkName: linkName,
      mode: mode,
      size: size,
      userName: userName,
      userId: userId,
      groupId: groupId,
      groupName: groupName,
      accessed: accessed,
      changed: changed,
      devMajor: devMajor,
      devMinor: devMinor,
    );
  }

  TarHeader._();
}

@internal
class HeaderImpl extends TarHeader {
  TypeFlag internalTypeFlag;

  @override
  String name;

  @override
  String? linkName;

  @override
  int mode;

  @override
  int userId;

  @override
  int groupId;

  @override
  String? userName;

  @override
  String? groupName;

  @override
  int size;

  @override
  DateTime modified;

  @override
  DateTime? accessed;

  @override
  DateTime? changed;

  @override
  int devMajor;

  @override
  int devMinor;

  @override
  TarFormat format;

  @override
  TypeFlag get typeFlag {
    return internalTypeFlag == TypeFlag.regA ? TypeFlag.reg : internalTypeFlag;
  }

  /// This constructor is meant to help us deal with header-only headers (i.e.
  /// meta-headers that only describe the next file instead of being a header
  /// to files themselves)
  HeaderImpl.internal({
    required this.name,
    required this.modified,
    required this.format,
    required TypeFlag typeFlag,
    this.linkName,
    this.mode = 0,
    this.size = -1,
    this.userName,
    this.userId = 0,
    this.groupId = 0,
    this.groupName,
    this.accessed,
    this.changed,
    this.devMajor = 0,
    this.devMinor = 0,
  })  : internalTypeFlag = typeFlag,
        super._();

  factory HeaderImpl.parseBlock(Uint8List headerBlock,
      {Map<String, String> paxHeaders = const {}}) {
    assert(headerBlock.length == 512);

    final format = _getFormat(headerBlock);
    final size = paxHeaders.size ?? headerBlock.readOctal(124, 12);

    // Start by reading data available in every format.
    final header = HeaderImpl.internal(
      format: format,
      name: headerBlock.readString(0, 100),
      mode: headerBlock.readOctal(100, 8),
      // These should be octal, but some weird tar implementations ignore that?!
      // Encountered with package:RAL, version 1.28.0 on pub
      userId: headerBlock.readNumeric(108, 8),
      groupId: headerBlock.readNumeric(116, 8),
      size: size,
      modified: secondsSinceEpoch(headerBlock.readOctal(136, 12)),
      typeFlag: typeflagFromByte(headerBlock[156]),
      linkName: headerBlock.readStringOrNullIfEmpty(157, 100),
    );

    if (header.hasContent && size < 0) {
      throw TarException.header('Indicates an invalid size of $size');
    }

    if (format.isValid() && format != TarFormat.v7) {
      // If it's a valid header that is not of the v7 format, it will have the
      // USTAR fields
      header
        ..userName ??= headerBlock.readStringOrNullIfEmpty(265, 32)
        ..groupName ??= headerBlock.readStringOrNullIfEmpty(297, 32)
        ..devMajor = headerBlock.readNumeric(329, 8)
        ..devMinor = headerBlock.readNumeric(337, 8);

      // Prefix to the file name
      var prefix = '';
      if (format.has(TarFormat.ustar) || format.has(TarFormat.pax)) {
        prefix = headerBlock.readString(345, 155);

        if (headerBlock.any(isNotAscii)) {
          header.format = format.mayOnlyBe(TarFormat.pax);
        }
      } else if (format.has(TarFormat.star)) {
        prefix = headerBlock.readString(345, 131);
        header
          ..accessed = secondsSinceEpoch(headerBlock.readNumeric(476, 12))
          ..changed = secondsSinceEpoch(headerBlock.readNumeric(488, 12));
      } else if (format.has(TarFormat.gnu)) {
        header.format = TarFormat.gnu;

        if (headerBlock[345] != 0) {
          header.accessed = secondsSinceEpoch(headerBlock.readNumeric(345, 12));
        }

        if (headerBlock[357] != 0) {
          header.changed = secondsSinceEpoch(headerBlock.readNumeric(357, 12));
        }
      }

      if (prefix.isNotEmpty) {
        header.name = '$prefix/${header.name}';
      }
    }

    return header.._applyPaxHeaders(paxHeaders);
  }

  void _applyPaxHeaders(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.value == '') {
        continue; // Keep the original USTAR value
      }

      switch (entry.key) {
        case paxPath:
          name = entry.value;
          break;
        case paxLinkpath:
          linkName = entry.value;
          break;
        case paxUname:
          userName = entry.value;
          break;
        case paxGname:
          groupName = entry.value;
          break;
        case paxUid:
          userId = parseInt(entry.value);
          break;
        case paxGid:
          groupId = parseInt(entry.value);
          break;
        case paxAtime:
          accessed = parsePaxTime(entry.value);
          break;
        case paxMtime:
          modified = parsePaxTime(entry.value);
          break;
        case paxCtime:
          changed = parsePaxTime(entry.value);
          break;
        case paxSize:
          size = parseInt(entry.value);
          break;
        default:
          break;
      }
    }
  }
}

/// Checks that [rawHeader] represents a valid tar header based on the
/// checksum, and then attempts to guess the specific format based
/// on magic values. If the checksum fails, then an error is thrown.
TarFormat _getFormat(Uint8List rawHeader) {
  final checksum = rawHeader.readOctal(checksumOffset, checksumLength);

  // Modern TAR archives use the unsigned checksum, but we check the signed
  // checksum as well for compatibility.
  if (checksum != rawHeader.computeUnsignedHeaderChecksum() &&
      checksum != rawHeader.computeSignedHeaderChecksum()) {
    throw TarException.header('Checksum does not match');
  }

  final hasUstarMagic = rawHeader.matchesHeader(magicUstar);
  if (hasUstarMagic) {
    return rawHeader.matchesHeader(trailerStar, offset: starTrailerOffset)
        ? TarFormat.star
        : TarFormat.ustar | TarFormat.pax;
  }

  if (rawHeader.matchesHeader(magicGnu) &&
      rawHeader.matchesHeader(versionGnu, offset: versionOffset)) {
    return TarFormat.gnu;
  }

  return TarFormat.v7;
}

extension _ReadPaxHeaders on Map<String, String> {
  int? get size {
    final sizeStr = this[paxSize];
    return sizeStr == null ? null : int.tryParse(sizeStr);
  }
}
