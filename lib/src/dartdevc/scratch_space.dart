// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import '../io.dart';

typedef Future<Asset> AssetReader(AssetId id);

/// An on-disk temporary environment for running executables that don't have
/// a standard Dart library API.
class ScratchSpace {
  final Directory tempDir;
  final Directory packagesDir;
  final AssetReader getAsset;

  // Assets which have a file created but it is still being written to.
  final _pendingWrites = <AssetId, Future>{};

  ScratchSpace._(Directory tempDir, this.getAsset)
      : packagesDir = new Directory(p.join(tempDir.path, 'packages')),
        this.tempDir = tempDir;

  factory ScratchSpace(Future<Asset> getAsset(AssetId id)) {
    var tempDir = new Directory(createSystemTempDir());
    return new ScratchSpace._(tempDir, getAsset);
  }

  /// Copies [assetIds] to [tempDir] if they don't exist.
  ///
  /// Any [Asset] that is under a `lib` dir will be output under a `packages`
  /// directory corresponding to its package, and any other assets are output
  /// directly under the temp dir using their unmodified path.
  Future ensureAssets(Iterable<AssetId> assetIds) async {
    var futures = <Future>[];
    for (var id in assetIds) {
      var file = fileFor(id);
      if (file.existsSync()) {
        var pending = _pendingWrites[id];
        if (pending != null) futures.add(pending);
      } else {
        file.createSync(recursive: true);
        var done = () async {
          var asset = await getAsset(id);
          await createFileFromStream(asset.read(), file.path);
          _pendingWrites.remove(id);
        }();
        _pendingWrites[id] = done;
        futures.add(done);
      }
    }
    return Future.wait(futures);
  }

  /// Deletes all files for [package] from the temp dir (synchronously).
  ///
  /// This always deletes the [package] dir under [packagesDir].
  ///
  /// If [isRootPackage] then this also deletes all top level entities under
  /// [tempDir] other than the [packagesDir].
  void deletePackageFiles(String package, {bool isRootPackage}) {
    isRootPackage ??= false;
    var packageDir = new Directory(p.join(packagesDir.path, package));
    if (packageDir.existsSync()) packageDir.deleteSync(recursive: true);
    if (isRootPackage) {
      var entities = tempDir.listSync(recursive: false);
      for (var entity in entities) {
        if (entity.path == packagesDir.path) continue;
        entity.deleteSync(recursive: true);
      }
    }
  }

  /// Deletes the temp directory for this environment.
  Future delete() async {
    if (await tempDir.exists()) return tempDir.delete(recursive: true);
  }

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
