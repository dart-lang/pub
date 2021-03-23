import 'dart:io';
import 'dart:typed_data';

import 'package:tar/tar.dart';

Future<void> main() async {
  // Generate tar file claiming to have a 7 GB header
  await Stream<TarEntry>.fromIterable([
    TarEntry.data(
      TarHeader(
        name: 'PaxHeader',
        mode: 0,
        typeFlag: TypeFlag.xHeader,
        size: 1024 * 1024 * 1024 * 7,
      ),
      Uint8List(0),
    ),
    TarEntry.data(
      TarHeader(
        name: 'test.txt',
        mode: 0,
      ),
      Uint8List(0),
    ),
  ])
      .transform(tarWriter)
      .pipe(File('reference/evil_large_header.tar').openWrite());
}
