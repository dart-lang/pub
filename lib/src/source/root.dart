// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../language_version.dart';
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';

class RootSource extends Source<RootDescription> {
  static final RootSource instance = RootSource._();

  RootSource._();

  @override
  String get name => 'root';

  @override
  Future<Pubspec> doDescribe(
    PackageId<RootDescription> id,
    SystemCache cache,
  ) async {
    return id.description.description.package.pubspec;
  }

  @override
  Future<List<PackageId<RootDescription>>> doGetVersions(
      PackageRef<RootDescription> ref, Duration? maxAge, SystemCache cache) {
    return Future.value([PackageId.root(ref.description.package)]);
  }

  @override
  String getDirectory(PackageId<RootDescription> id, SystemCache cache,
      {String? relativeFrom}) {
    // TODO(sigurdm): Should we support this.
    throw UnsupportedError('Cannot get the directory of the root package');
  }

  @override
  PackageId<RootDescription> parseId(String name, Version version, description,
      {String? containingDir}) {
    throw UnsupportedError('Trying to parse a root package description.');
  }

  @override
  PackageRef<RootDescription> parseRef(String name, description,
      {String? containingDir, required LanguageVersion languageVersion}) {
    throw UnsupportedError('Trying to parse a root package description.');
  }
}

class ResolvedRootDescription extends ResolvedDescription<RootDescription> {
  ResolvedRootDescription(RootDescription description) : super(description);

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

class RootDescription extends Description<RootDescription> {
  final Package package;

  RootDescription(this.package);
  @override
  String format({required String? containingDir}) {
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
  Source<RootDescription> get source => RootSource.instance;

  @override
  bool operator ==(Object other) =>
      other is RootDescription && other.package == package;

  @override
  int get hashCode => 'root'.hashCode;
}
