// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import 'package.dart';
import 'source.dart';
import 'source/hosted.dart';
import 'source/root.dart';
import 'system_cache.dart';

/// A reference to a [Package], but not any particular version(s) of it.
///
/// It knows the [name] of a package and a [Description] that is connected
/// with a certain [Source]. This is what you need for listing available
/// versions of a package. See [SystemCache.getVersions].
class PackageRef {
  final String name;
  final Description description;
  bool get isRoot => description is RootDescription;
  Source get source => description.source;

  /// Creates a reference to a package with the given [name], and
  /// [description].
  PackageRef(this.name, this.description);

  /// Creates a reference to the given root package.
  static PackageRef root(Package package) =>
      PackageRef(package.name, RootDescription(package));

  @override
  String toString([PackageDetail? detail]) {
    detail ??= PackageDetail.defaults;
    if (isRoot) return name;

    var buffer = StringBuffer(name);
    if (detail.showSource ?? description is! HostedDescription) {
      buffer.write(' from ${description.source}');
      if (detail.showDescription) {
        buffer.write(' ${description.format()}');
      }
    }

    return buffer.toString();
  }

  PackageRange withConstraint(VersionConstraint constraint) =>
      PackageRange(this, constraint);

  @override
  bool operator ==(other) =>
      other is PackageRef &&
      name == other.name &&
      description == other.description;

  @override
  int get hashCode => Object.hash(name, description);
}

/// A reference to a specific version of a package.
///
/// A package ID contains enough information to correctly retrieve the package.
///
/// It's possible for multiple distinct package IDs to point to different
/// packages that have identical contents. For example, the same package may be
/// available from multiple sources. As far as Pub is concerned, those packages
/// are different.
///
/// Note that a package ID's [description] field is a [ResolvedDescription]
/// while [PackageRef.description] and [PackageRange.description] are
/// [Description]s.
class PackageId {
  final String name;
  final Version version;
  final ResolvedDescription description;
  bool get isRoot => description is ResolvedRootDescription;
  Source get source => description.description.source;

  /// Creates an ID for a package with the given [name], [source], [version],
  /// and [description].
  ///
  /// Since an ID's description is an implementation detail of its source, this
  /// should generally not be called outside of [Source] subclasses.
  PackageId(this.name, this.version, this.description);

  /// Creates an ID for the given root package.
  static PackageId root(Package package) => PackageId(
        package.name,
        package.version,
        ResolvedRootDescription(RootDescription(package)),
      );

  @override
  int get hashCode => Object.hash(name, version, description);

  @override
  bool operator ==(other) =>
      other is PackageId &&
      name == other.name &&
      version == other.version &&
      description == other.description;

  /// Returns a [PackageRange] that allows only [version] of this package.
  PackageRange toRange() => PackageRange(toRef(), version);

  PackageRef toRef() => PackageRef(name, description.description);

  @override
  String toString([PackageDetail? detail]) {
    detail ??= PackageDetail.defaults;

    var buffer = StringBuffer(name);
    if (detail.showVersion ?? !isRoot) buffer.write(' $version');

    if (!isRoot &&
        (detail.showSource ?? description is! ResolvedHostedDescription)) {
      buffer.write(' from ${description.description.source}');
      if (detail.showDescription) {
        buffer.write(' ${description.format()}');
      }
    }

    return buffer.toString();
  }
}

/// A reference to a constrained range of versions of one package.
///
/// This is represented as a [PackageRef] and a [VersionConstraint].
class PackageRange {
  final PackageRef _ref;

  /// The allowed package versions.
  final VersionConstraint constraint;

  String get name => _ref.name;
  Description get description => _ref.description;
  bool get isRoot => _ref.isRoot;
  Source get source => _ref.source;

  /// Creates a reference to package with the given [name], [source],
  /// [constraint], and [description].
  ///
  /// Since an ID's description is an implementation detail of its source, this
  /// should generally not be called outside of [Source] subclasses.
  PackageRange(this._ref, this.constraint);

  /// Creates a range that selects the root package.
  static PackageRange root(Package package) =>
      PackageRange(PackageRef.root(package), package.version);

  PackageRef toRef() => _ref;

  @override
  String toString([PackageDetail? detail]) {
    detail ??= PackageDetail.defaults;

    var buffer = StringBuffer(name);
    if (detail.showVersion ?? _showVersionConstraint) {
      buffer.write(' $constraint');
    }

    if (!isRoot && (detail.showSource ?? description is! HostedDescription)) {
      buffer.write(' from ${description.source.name}');
      if (detail.showDescription) {
        buffer.write(' ${description.format()}');
      }
    }
    return buffer.toString();
  }

  /// Whether to include the version constraint in [toString] by default.
  bool get _showVersionConstraint {
    if (isRoot) return false;
    if (!constraint.isAny) return true;
    return description.source.hasMultipleVersions;
  }

  /// Returns a copy of [this] with the same semantics, but with a `^`-style
  /// constraint if possible.
  PackageRange withTerseConstraint() {
    if (constraint is! VersionRange) return this;
    if (constraint.toString().startsWith('^')) return this;

    var range = constraint as VersionRange;
    if (!range.includeMin) return this;
    if (range.includeMax) return this;
    var min = range.min;
    if (min == null) return this;
    if (range.max == min.nextBreaking.firstPreRelease) {
      return PackageRange(_ref, VersionConstraint.compatibleWith(min));
    } else {
      return this;
    }
  }

  /// Whether [id] satisfies this dependency.
  ///
  /// Specifically, whether [id] refers to the same package as [this] *and*
  /// [constraint] allows `id.version`.
  bool allows(PackageId id) =>
      name == id.name &&
      description == id.description.description &&
      constraint.allows(id.version);

  @override
  int get hashCode => Object.hash(_ref, constraint);

  @override
  bool operator ==(other) =>
      other is PackageRange &&
      _ref == other._ref &&
      other.constraint == constraint;
}

/// An enum of different levels of detail that can be used when displaying a
/// terse package name.
class PackageDetail {
  /// The default [PackageDetail] configuration.
  static const defaults = PackageDetail();

  /// Whether to show the package version or version range.
  ///
  /// If this is `null`, the version is shown for all packages other than root
  /// [PackageId]s or [PackageRange]s with `git` or `path` sources and `any`
  /// constraints.
  final bool? showVersion;

  /// Whether to show the package source.
  ///
  /// If this is `null`, the source is shown for all non-hosted, non-root
  /// packages. It's always `true` if [showDescription] is `true`.
  final bool? showSource;

  /// Whether to show the package description.
  ///
  /// This defaults to `false`.
  final bool showDescription;

  const PackageDetail({
    this.showVersion,
    bool? showSource,
    bool? showDescription,
  })  : showSource = showDescription == true ? true : showSource,
        showDescription = showDescription ?? false;

  /// Returns a [PackageDetail] with the maximum amount of detail between [this]
  /// and [other].
  PackageDetail max(PackageDetail other) => PackageDetail(
        showVersion: showVersion! || other.showVersion!,
        showSource: showSource! || other.showSource!,
        showDescription: showDescription || other.showDescription,
      );
}
