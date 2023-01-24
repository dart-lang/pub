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
    final description = id.description.description;
    if (description is! RootDescription) {
      throw ArgumentError('Wrong source');
    }
    return description.package.pubspec;
  }

  @override
  Future<List<PackageId>> doGetVersions(
    PackageRef ref,
    Duration? maxAge,
    SystemCache cache,
  ) async {
    final description = ref.description;
    if (description is! RootDescription) {
      throw ArgumentError('Wrong source');
    }
    return [PackageId.root(description.package)];
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
    description, {
    String? containingDir,
  }) {
    throw UnsupportedError('Trying to parse a root package description.');
  }

  @override
  PackageRef parseRef(
    String name,
    description, {
    String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    throw UnsupportedError('Trying to parse a root package description.');
  }
}

class ResolvedRootDescription extends ResolvedDescription {
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

class RootDescription extends Description {
  final Package package;

  RootDescription(this.package);
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
      other is RootDescription && other.package == package;

  @override
  int get hashCode => 'root'.hashCode;
}
