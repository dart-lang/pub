// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import '../../io.dart';

/// An on-disk temporary environment for running executables that don't have
/// a standard Dart library API.
class ScratchSpace {
  final Directory tempDir;
  final Directory packagesDir;

  ScratchSpace._(Directory tempDir)
      : packagesDir = new Directory(p.join(tempDir.path, 'packages')),
        this.tempDir = tempDir;

  /// Creates a new [ScratchSpace] containing [assetIds].
  ///
  /// Any [Asset] that is under a `lib` dir will be output under a `packages`
  /// directory corresponding to its package, and any other assets are output
  /// directly under the temp dir using their unmodified path.
  static Future<ScratchSpace> create(
      Iterable<AssetId> assetIds, Stream<List<int>> readAsset(AssetId)) async {
    var tempDir = new Directory(createSystemTempDir());
    var futures = <Future>[];
    for (var id in assetIds) {
      var filePath = p.join(tempDir.path, _relativePathFor(id));
      var file = new File(filePath)..createSync(recursive: true);
      await readAsset(id).pipe(file.openWrite());
    }
    await Future.wait(futures);
    return new ScratchSpace._(tempDir);
  }

  /// Deletes the temp directory for this environment.
  Future delete() => tempDir.delete(recursive: true);

  /// Returns the actual [File] in this environment corresponding to [id].
  ///
  /// The returned [File] may or may not already exist.
  File fileFor(AssetId id) =>
      new File(p.join(tempDir.path, _relativePathFor(id)));
}

/// Returns a canonical uri for [id].
///
/// If [id] is under a `lib` directory then this returns a `package:` uri,
/// otherwise it just returns [id.path].
String canonicalUriFor(AssetId id) {
  if (topLevelDir(id.path) == 'lib') {
    var packagePath =
        p.url.join(id.package, p.url.joinAll(p.url.split(id.path).skip(1)));
    return 'package:$packagePath';
  } else {
    return id.path;
  }
}

/// The path relative to the root of the environment for a given [id].
String _relativePathFor(AssetId id) =>
    canonicalUriFor(id).replaceFirst('package:', 'packages/');
