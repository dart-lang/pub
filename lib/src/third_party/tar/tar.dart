/// Streaming tar implementation for Dart.
///
/// To read tar files, see [TarReader]. To write tar files, use [tarWritingSink]
///  or [tarWriter].
library tar;

// For dartdoc.
import 'src/reader.dart';
import 'src/writer.dart';

export 'src/constants.dart' show TypeFlag;
export 'src/entry.dart' show TarEntry, SynchronousTarEntry;
export 'src/exception.dart';
export 'src/format.dart';
export 'src/header.dart' show TarHeader;
export 'src/reader.dart' show TarReader;
export 'src/writer.dart';
