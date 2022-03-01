import 'dart:typed_data';

import 'charcodes.dart';
import 'exception.dart';
import 'header.dart' show TarHeader; // for dartdoc

// Magic values to help us identify the TAR header type.
const magicGnu = [$u, $s, $t, $a, $r, $space]; // 'ustar '
const versionGnu = [$space, 0]; // ' \x00'
const magicUstar = [$u, $s, $t, $a, $r, 0]; // 'ustar\x00'
const versionUstar = [$0, $0]; // '00'
const trailerStar = [$t, $a, $r, 0]; // 'tar\x00'

/// Type flags for [TarHeader].
///
/// The type flag of a header indicates the kind of file associated with the
/// entry. This enum contains the various type flags over the different TAR
/// formats, and users should be careful that the type flag corresponds to the
/// TAR format they are working with.
enum TypeFlag {
  /// [reg] indicates regular files.
  ///
  /// Old tar implementations have a seperate `TypeRegA` value. This library
  /// will transparently read those as [regA].
  reg,

  /// Legacy-version of [reg] in old tar implementations.
  ///
  /// This is only used internally.
  regA,

  /// Hard link - header-only, may not have a data body
  link,

  /// Symbolic link - header-only, may not have a data body
  symlink,

  /// Character device node - header-only, may not have a data body
  char,

  /// Block device node - header-only, may not have a data body
  block,

  /// Directory - header-only, may not have a data body
  dir,

  /// FIFO node - header-only, may not have a data body
  fifo,

  /// Currently does not have any meaning, but is reserved for the future.
  reserved,

  /// Used by the PAX format to store key-value records that are only relevant
  /// to the next file.
  ///
  /// This package transparently handles these types.
  xHeader,

  /// Used by the PAX format to store key-value records that are relevant to all
  /// subsequent files.
  ///
  /// This package only supports parsing and composing such headers,
  /// but does not currently support persisting the global state across files.
  xGlobalHeader,

  /// Indiates a sparse file in the GNU format
  gnuSparse,

  /// Used by the GNU format for a meta file to store the path or link name for
  /// the next file.
  /// This package transparently handles these types.
  gnuLongName,
  gnuLongLink,

  /// Vendor specific typeflag, as defined in POSIX.1-1998. Seen as outdated but
  /// may still exist on old files.
  ///
  /// This library uses a single enum to catch them all.
  vendor
}

/// Generates the corresponding [TypeFlag] associated with [byte].
TypeFlag typeflagFromByte(int byte) {
  switch (byte) {
    case $0:
      return TypeFlag.reg;
    case 0:
      return TypeFlag.regA;
    case $1:
      return TypeFlag.link;
    case $2:
      return TypeFlag.symlink;
    case $3:
      return TypeFlag.char;
    case $4:
      return TypeFlag.block;
    case $5:
      return TypeFlag.dir;
    case $6:
      return TypeFlag.fifo;
    case $7:
      return TypeFlag.reserved;
    case $x:
      return TypeFlag.xHeader;
    case $g:
      return TypeFlag.xGlobalHeader;
    case $S:
      return TypeFlag.gnuSparse;
    case $L:
      return TypeFlag.gnuLongName;
    case $K:
      return TypeFlag.gnuLongLink;
    default:
      if (64 < byte && byte < 91) {
        return TypeFlag.vendor;
      }
      throw TarException.header('Invalid typeflag value $byte');
  }
}

int typeflagToByte(TypeFlag flag) {
  switch (flag) {
    case TypeFlag.reg:
    case TypeFlag.regA:
      return $0;
    case TypeFlag.link:
      return $1;
    case TypeFlag.symlink:
      return $2;
    case TypeFlag.char:
      return $3;
    case TypeFlag.block:
      return $4;
    case TypeFlag.dir:
      return $5;
    case TypeFlag.fifo:
      return $6;
    case TypeFlag.reserved:
      return $7;
    case TypeFlag.xHeader:
      return $x;
    case TypeFlag.xGlobalHeader:
      return $g;
    case TypeFlag.gnuSparse:
      return $S;
    case TypeFlag.gnuLongName:
      return $L;
    case TypeFlag.gnuLongLink:
      return $K;
    case TypeFlag.vendor:
      throw ArgumentError("Can't write vendor-specific type-flags");
  }
}

/// Keywords for PAX extended header records.
const paxPath = 'path';
const paxLinkpath = 'linkpath';
const paxSize = 'size';
const paxUid = 'uid';
const paxGid = 'gid';
const paxUname = 'uname';
const paxGname = 'gname';
const paxMtime = 'mtime';
const paxAtime = 'atime';
const paxCtime =
    'ctime'; // Removed from later revision of PAX spec, but was valid
const paxComment = 'comment';
const paxSchilyXattr = 'SCHILY.xattr.';

/// Keywords for GNU sparse files in a PAX extended header.
const paxGNUSparse = 'GNU.sparse.';
const paxGNUSparseNumBlocks = 'GNU.sparse.numblocks';
const paxGNUSparseOffset = 'GNU.sparse.offset';
const paxGNUSparseNumBytes = 'GNU.sparse.numbytes';
const paxGNUSparseMap = 'GNU.sparse.map';
const paxGNUSparseName = 'GNU.sparse.name';
const paxGNUSparseMajor = 'GNU.sparse.major';
const paxGNUSparseMinor = 'GNU.sparse.minor';
const paxGNUSparseSize = 'GNU.sparse.size';
const paxGNUSparseRealSize = 'GNU.sparse.realsize';

/// A set of pax header keys supported by this library.
///
/// The reader will ignore pax headers not listed in this map.
const supportedPaxHeaders = {
  paxPath,
  paxLinkpath,
  paxSize,
  paxUid,
  paxGid,
  paxUname,
  paxGname,
  paxMtime,
  paxAtime,
  paxCtime,
  paxComment,
  paxSchilyXattr,
  paxGNUSparse,
  paxGNUSparseNumBlocks,
  paxGNUSparseOffset,
  paxGNUSparseNumBytes,
  paxGNUSparseMap,
  paxGNUSparseName,
  paxGNUSparseMajor,
  paxGNUSparseMinor,
  paxGNUSparseSize,
  paxGNUSparseRealSize
};

/// User ID bit
const c_ISUID = 2048;

/// Group ID bit
const c_ISGID = 1024;

/// Sticky bit
const c_ISVTX = 512;

/// Constants to determine file modes.
const modeType = 2401763328;
const modeSymLink = 134217728;
const modeDevice = 67108864;
const modeCharDevice = 2097152;
const modeNamedPipe = 33554432;
const modeSocket = 1677216;
const modeSetUid = 8388608;
const modeSetGid = 4194304;
const modeSticky = 1048576;
const modeDirectory = 2147483648;

/// The offset of the checksum in the header
const checksumOffset = 148;
const checksumLength = 8;
const magicOffset = 257;
const versionOffset = 263;
const starTrailerOffset = 508;

/// Size constants from various TAR specifications.
/// Size of each block in a TAR stream.
const blockSize = 512;
const blockSizeLog2 = 9;
const maxIntFor12CharOct = 0x1ffffffff; // 777 7777 7777 in oct

const defaultSpecialLength = 4 * blockSize;

/// Max length of the name field in USTAR format.
const nameSize = 100;

/// Max length of the prefix field in USTAR format.
const prefixSize = 155;

/// A full TAR block of zeros.
final zeroBlock = Uint8List(blockSize);
