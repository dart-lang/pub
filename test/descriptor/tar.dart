// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as path;
import 'package:pub/src/io.dart';
import 'package:test_descriptor/test_descriptor.dart';

/// Describes a tar file and its contents.
class TarFileDescriptor extends FileDescriptor {
  final List<Descriptor> contents;

  TarFileDescriptor(String name, Iterable<Descriptor> contents)
      : contents = contents.toList(),
        super.protected(name);

  /// Creates the files and directories within this tar file, then archives
  /// them, compresses them, and saves the result to [parentDir].
  Future create([String parent]) {
    return withTempDir((tempDir) async {
      await Future.wait(contents.map((entry) => entry.create(tempDir)));

      var createdContents = listDir(tempDir,
          recursive: true, includeHidden: true, includeDirs: false);
      var bytes =
          await createTarGz(createdContents, baseDir: tempDir).toBytes();

      var file = path.join(parent ?? sandbox, name);
      writeBinaryFile(file, bytes);
      return file;
    });
  }

  /// Validates that the `.tar.gz` file at [path] contains the expected
  /// contents.
  Future validate([String parent]) {
    throw new UnimplementedError("TODO(nweiz): implement this");
  }

  Future<String> read() =>
      throw new UnsupportedError("TarFileDescriptor.read() is not supported.");

  Stream<List<int>> readAsBytes() {
    return new Stream<List<int>>.fromFuture(withTempDir((tempDir) async {
      await create(tempDir);
      return await readBinaryFile(path.join(tempDir, name));
    }));
  }
}
