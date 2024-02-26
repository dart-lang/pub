// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../language_version.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';

/// A root package is the root of a package dependency graph that seeds a
/// version resolution.
///
/// There is no explicit way to depend on a root package.
///
/// A root package is the only package for which dev_dependencies are taken into
/// account.
///
/// A root package is the only package for which dependency_overrides are taken
/// into account.
class RootSource extends Source {
  static final RootSource instance = RootSource._();

  RootSource._();

  @override
  String get name => 'root';

  @override
  Future<Pubspec> doDescribe(
    PackageId id,
    SystemCache cache,
  ) async {
    throw UnsupportedError('Cannot describe the root');
  }

  @override
  Future<List<PackageId>> doGetVersions(
    PackageRef ref,
    Duration? maxAge,
    SystemCache cache,
  ) async {
    throw UnsupportedError('Trying to get versions of the root package');
  }

  @override
  String doGetDirectory(
    PackageId id,
    SystemCache cache, {
    String? relativeFrom,
  }) {
    // TODO(sigurdm): Should we support this.
    throw UnsupportedError('Cannot get the directory of the root package');
  }

  @override
  PackageId parseId(
    String name,
    Version version,
    Object? description, {
    String? containingDir,
  }) {
    throw UnsupportedError('Trying to parse a root package description.');
  }

  @override
  PackageRef parseRef(
    String name,
    Object? description, {
    String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    throw UnsupportedError('Trying to parse a root package description.');
  }
}

class ResolvedRootDescription extends ResolvedDescription {
  @override
  RootDescription get description => super.description as RootDescription;

  ResolvedRootDescription(RootDescription super.description);

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    throw UnsupportedError('Trying to serialize a root package description.');
  }

  @override
  bool operator ==(Object other) =>
      other is ResolvedRootDescription && other.description == description;

  @override
  int get hashCode => description.hashCode;
}

class RootDescription extends Description {
  final String path;

  RootDescription(this.path);
  @override
  String format() {
    throw UnsupportedError('Trying to format a root package description.');
  }

  @override
  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    throw UnsupportedError('Trying to serialize the root package description.');
  }

  @override
  Source get source => RootSource.instance;

  @override
  bool operator ==(Object other) =>
      other is RootDescription && other.path == path;

  @override
  int get hashCode => 'root'.hashCode;
}
