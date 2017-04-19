// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import '../../io.dart';
import 'util.dart';

/// An on-disk temporary environment for running executables that don't have
/// a standard dart library api.
class TempEnvironment {
  final Directory tempDir;
  final Directory packagesDir;

  TempEnvironment._(Directory tempDir)
      : packagesDir = new Directory(p.join(tempDir.path, 'packages')),
        this.tempDir = tempDir;

  /// Creates a new [TempEnvironment] containing [assetIds].
  ///
  /// Any [Asset] that is under a `lib` dir will be output under a `packages`
  /// folder corresponding to it's package, and any other assets are output
  /// directly under the temp dir using their unmodified path.
  static Future<TempEnvironment> create(
      Iterable<AssetId> assetIds, Stream<List<int>> readAsset(AssetId)) async {
    var tempDir = await Directory.systemTemp.createTemp('pub_');
    var futures = <Future>[];
    for (var id in assetIds) {
      var filePath = p.join(tempDir.path, relativePathFor(id));
      new File(filePath).createSync(recursive: true);
      futures.add(createFileFromStream(readAsset(id), filePath));
    }
    await Future.wait(futures);
    return new TempEnvironment._(tempDir);
  }

  /// Deletes the temp directory for this environment.
  Future delete() => tempDir.delete(recursive: true);

  /// Returns the actual [File] in this environment corresponding to [id].
  ///
  /// The returned [File] may or may not already exist.
  File fileFor(AssetId id) =>
      new File(p.join(tempDir.path, relativePathFor(id)));
}

/// The path relative to the root of the environment for a given [id].
String relativePathFor(AssetId id) =>
    canonicalUriFor(id).replaceFirst('package:', 'packages/');
