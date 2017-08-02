// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';

/// A [Null Object] that represents a source not recognized by pub.
///
/// It provides some default behavior so that pub can work with sources it
/// doesn't recognize.
///
/// [null object]: http://en.wikipedia.org/wiki/Null_Object_pattern
class UnknownSource extends Source {
  final String name;

  UnknownSource(this.name);

  BoundSource bind(SystemCache systemCache) =>
      new _BoundUnknownSource(this, systemCache);

  /// Two unknown sources are the same if their names are the same.
  bool operator ==(other) => other is UnknownSource && other.name == name;

  int get hashCode => name.hashCode;

  bool descriptionsEqual(description1, description2) =>
      description1 == description2;

  int hashDescription(description) => description.hashCode;

  PackageRef parseRef(String name, description, {String containingPath}) =>
      new PackageRef(name, this, description);

  PackageId parseId(String name, Version version, description) =>
      new PackageId(name, this, version, description);
}

class _BoundUnknownSource extends BoundSource {
  final UnknownSource source;

  final SystemCache systemCache;

  _BoundUnknownSource(this.source, this.systemCache);

  Future<List<PackageId>> doGetVersions(PackageRef ref) =>
      throw new UnsupportedError(
          "Cannot get package versions from unknown source '${source.name}'.");

  Future<Pubspec> doDescribe(PackageId id) => throw new UnsupportedError(
      "Cannot describe a package from unknown source '${source.name}'.");

  Future get(PackageId id, String symlink) => throw new UnsupportedError(
      "Cannot get an unknown source '${source.name}'.");

  /// Returns the directory where this package can be found locally.
  String getDirectory(PackageId id) => throw new UnsupportedError(
      "Cannot find a package from an unknown source '${source.name}'.");
}
