// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:pub/src/log.dart' as log;
import 'package:test_descriptor/test_descriptor.dart';

/// Describes a tar file and its contents.
class TarFileDescriptor extends FileDescriptor {
  final List<Descriptor> contents;

  TarFileDescriptor(super.name, Iterable<Descriptor> contents)
    : contents = contents.toList(),
      super.protected();

  /// Creates the files and directories within this tar file, then archives
  /// them, compresses them, and saves the result to [parent].
  @override
  Future create([String? parent]) {
    return withTempDir((tempDir) async {
      await Future.wait(contents.map((entry) => entry.create(tempDir)));

      final createdContents = listDir(
        tempDir,
        recursive: true,
        includeHidden: true,
        includeDirs: false,
      );
      final bytes =
          await createTarGz(createdContents, baseDir: tempDir).toBytes();

      final file = p.join(parent ?? sandbox, name);
      _writeBinaryFile(file, bytes);
      return file;
    });
  }

  /// Validates that the `.tar.gz` file at [path] contains the expected
  /// contents.
  @override
  Future validate([String? parent]) {
    throw UnimplementedError('TODO(nweiz): implement this');
  }

  @override
  Future<String> read() =>
      throw UnsupportedError('TarFileDescriptor.read() is not supported.');

  @override
  Stream<List<int>> readAsBytes() {
    return Stream<List<int>>.fromFuture(
      withTempDir((tempDir) async {
        await create(tempDir);
        return readBinaryFile(p.join(tempDir, name));
      }),
    );
  }
}

/// Creates [file] and writes [contents] to it.
String _writeBinaryFile(String file, List<int> contents) {
  log.io('Writing ${contents.length} bytes to binary file $file.');
  deleteIfLink(file);
  File(file).openSync(mode: FileMode.write)
    ..writeFromSync(contents)
    ..closeSync();
  log.fine('Wrote text file $file.');
  return file;
}
