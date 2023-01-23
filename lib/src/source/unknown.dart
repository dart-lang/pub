// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

import '../language_version.dart';
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
  @override
  final String name;

  UnknownSource(this.name);

  /// Two unknown sources are the same if their names are the same.
  @override
  bool operator ==(other) => other is UnknownSource && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  PackageRef parseRef(
    String name,
    Object? description, {
    String? containingDir,
    LanguageVersion? languageVersion,
  }) =>
      PackageRef(name, UnknownDescription(description, this));

  @override
  PackageId parseId(
    String name,
    Version version,
    Object? description, {
    String? containingDir,
  }) =>
      PackageId(
        name,
        version,
        ResolvedUnknownDescription(UnknownDescription(description, this)),
      );

  @override
  Future<List<PackageId>> doGetVersions(
    PackageRef ref,
    Duration? maxAge,
    SystemCache cache,
  ) =>
      throw UnsupportedError(
        "Cannot get package versions from unknown source '$name'.",
      );

  @override
  Future<Pubspec> doDescribe(PackageId id, SystemCache cache) =>
      throw UnsupportedError(
        "Cannot describe a package from unknown source '$name'.",
      );

  /// Returns the directory where this package can be found locally.
  @override
  String doGetDirectory(
    PackageId id,
    SystemCache cache, {
    String? relativeFrom,
  }) =>
      throw UnsupportedError(
        "Cannot find a package from an unknown source '$name'.",
      );
}

class UnknownDescription extends Description {
  final Object? description;
  @override
  final UnknownSource source;
  UnknownDescription(this.description, this.source);

  @override
  String format() {
    return json.encode(description);
  }

  @override
  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    throw UnsupportedError(
      "Cannot serialize a package description from an unknown source '${source.name}'.",
    );
  }

  @override
  operator ==(Object other) =>
      other is UnknownDescription &&
      source.name == other.source.name &&
      json.encode(description) == json.encode(other.description);

  @override
  int get hashCode => Object.hash(source.name, json.encode(description));
}

class ResolvedUnknownDescription extends ResolvedDescription {
  ResolvedUnknownDescription(UnknownDescription description)
      : super(description);

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    throw UnsupportedError(
      "Cannot serialize a package description from an unknown source '${description.source.name}'.",
    );
  }

  @override
  operator ==(Object other) =>
      other is ResolvedUnknownDescription && description == other.description;

  @override
  int get hashCode => description.hashCode;
}
