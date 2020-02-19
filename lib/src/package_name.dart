// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

import 'package.dart';
import 'source.dart';
import 'source/git.dart';
import 'source/hosted.dart';
import 'source/path.dart';
import 'utils.dart';

/// The equality to use when comparing the feature sets of two package names.
const _featureEquality = MapEquality<String, FeatureDependency>();

/// The base class of [PackageRef], [PackageId], and [PackageRange].
abstract class PackageName {
  /// The name of the package being identified.
  final String name;

  /// The [Source] used to look up this package.
  ///
  /// If this is a root package, this will be `null`.
  final Source source;

  /// The metadata used by the package's [source] to identify and locate it.
  ///
  /// It contains whatever [Source]-specific data it needs to be able to get
  /// the package. For example, the description of a git sourced package might
  /// by the URL "git://github.com/dart/uilib.git".
  final dynamic description;

  /// Whether this is a name for a magic package.
  ///
  /// Magic packages are unversioned pub constructs that have special semantics.
  /// For example, a magic package named "pub itself" is inserted into the
  /// dependency graph when any package depends on barback. This packages has
  /// dependencies that represent the versions of barback and related packages
  /// that pub is compatible with.
  final bool isMagic;

  /// Whether this package is the root package.
  bool get isRoot => source == null && !isMagic;

  PackageName._(this.name, this.source, this.description) : isMagic = false;

  PackageName._magic(this.name)
      : source = null,
        description = null,
        isMagic = true;

  /// Returns a [PackageRef] with this one's [name], [source], and
  /// [description].
  PackageRef toRef() =>
      isMagic ? PackageRef.magic(name) : PackageRef(name, source, description);

  /// Returns a [PackageRange] for this package with the given version constraint.
  PackageRange withConstraint(VersionConstraint constraint) =>
      PackageRange(name, source, constraint, description);

  /// Returns whether this refers to the same package as [other].
  ///
  /// This doesn't compare any constraint information; it's equivalent to
  /// `this.toRef() == other.toRef()`.
  bool samePackage(PackageName other) {
    if (other.name != name) return false;
    if (source == null) return other.source == null;

    return other.source == source &&
        source.descriptionsEqual(description, other.description);
  }

  @override
  int get hashCode {
    if (source == null) return name.hashCode;
    return name.hashCode ^
        source.hashCode ^
        source.hashDescription(description);
  }

  /// Returns a string representation of this package name.
  ///
  /// If [detail] is passed, it controls exactly which details are included.
  @override
  String toString([PackageDetail detail]);
}

/// A reference to a [Package], but not any particular version(s) of it.
class PackageRef extends PackageName {
  /// Creates a reference to a package with the given [name], [source], and
  /// [description].
  ///
  /// Since an ID's description is an implementation detail of its source, this
  /// should generally not be called outside of [Source] subclasses. A reference
  /// can be obtained from a user-supplied description using [Source.parseRef].
  PackageRef(String name, Source source, description)
      : super._(name, source, description);

  /// Creates a reference to the given root package.
  PackageRef.root(Package package) : super._(package.name, null, package.name);

  /// Creates a reference to a magic package (see [isMagic]).
  PackageRef.magic(String name) : super._magic(name);

  @override
  String toString([PackageDetail detail]) {
    detail ??= PackageDetail.defaults;
    if (isMagic || isRoot) return name;

    var buffer = StringBuffer(name);
    if (detail.showSource ?? source is! HostedSource) {
      buffer.write(' from $source');
      if (detail.showDescription) {
        buffer.write(' ${source.formatDescription(description)}');
      }
    }

    return buffer.toString();
  }

  @override
  bool operator ==(other) => other is PackageRef && samePackage(other);
}

/// A reference to a specific version of a package.
///
/// A package ID contains enough information to correctly get the package.
///
/// It's possible for multiple distinct package IDs to point to different
/// packages that have identical contents. For example, the same package may be
/// available from multiple sources. As far as Pub is concerned, those packages
/// are different.
///
/// Note that a package ID's [description] field has a different structure than
/// the [PackageRef.description] or [PackageRange.description] fields for some
/// sources. For example, the `git` source adds revision information to the
/// description to ensure that the same ID always points to the same source.
class PackageId extends PackageName {
  /// The package's version.
  final Version version;

  /// Creates an ID for a package with the given [name], [source], [version],
  /// and [description].
  ///
  /// Since an ID's description is an implementation detail of its source, this
  /// should generally not be called outside of [Source] subclasses.
  PackageId(String name, Source source, this.version, description)
      : super._(name, source, description);

  /// Creates an ID for a magic package (see [isMagic]).
  PackageId.magic(String name)
      : version = Version.none,
        super._magic(name);

  /// Creates an ID for the given root package.
  PackageId.root(Package package)
      : version = package.version,
        super._(package.name, null, package.name);

  @override
  int get hashCode => super.hashCode ^ version.hashCode;

  @override
  bool operator ==(other) =>
      other is PackageId && samePackage(other) && other.version == version;

  /// Returns a [PackageRange] that allows only [version] of this package.
  PackageRange toRange() => withConstraint(version);

  @override
  String toString([PackageDetail detail]) {
    detail ??= PackageDetail.defaults;
    if (isMagic) return name;

    var buffer = StringBuffer(name);
    if (detail.showVersion ?? !isRoot) buffer.write(' $version');

    if (!isRoot && (detail.showSource ?? source is! HostedSource)) {
      buffer.write(' from $source');
      if (detail.showDescription) {
        buffer.write(' ${source.formatDescription(description)}');
      }
    }

    return buffer.toString();
  }
}

/// A reference to a constrained range of versions of one package.
class PackageRange extends PackageName {
  /// The allowed package versions.
  final VersionConstraint constraint;

  /// The dependencies declared on features of the target package.
  final Map<String, FeatureDependency> features;

  /// Creates a reference to package with the given [name], [source],
  /// [constraint], and [description].
  ///
  /// Since an ID's description is an implementation detail of its source, this
  /// should generally not be called outside of [Source] subclasses.
  PackageRange(String name, Source source, this.constraint, description,
      {Map<String, FeatureDependency> features})
      : features = features == null
            ? const {}
            : UnmodifiableMapView(Map.from(features)),
        super._(name, source, description);

  PackageRange.magic(String name)
      : constraint = Version.none,
        features = const {},
        super._magic(name);

  /// Creates a range that selects the root package.
  PackageRange.root(Package package)
      : constraint = package.version,
        features = const {},
        super._(package.name, null, package.name);

  /// Returns a description of [features], or the empty string if [features] is
  /// empty.
  String get featureDescription {
    if (features.isEmpty) return '';

    var enabledFeatures = <String>[];
    var disabledFeatures = <String>[];
    features.forEach((name, type) {
      if (type == FeatureDependency.unused) {
        disabledFeatures.add(name);
      } else {
        enabledFeatures.add(name);
      }
    });

    var description = '';
    if (enabledFeatures.isNotEmpty) {
      description += 'with ${toSentence(enabledFeatures)}';
      if (disabledFeatures.isNotEmpty) description += ', ';
    }

    if (disabledFeatures.isNotEmpty) {
      description += 'without ${toSentence(disabledFeatures)}';
    }
    return description;
  }

  @override
  String toString([PackageDetail detail]) {
    detail ??= PackageDetail.defaults;
    if (isMagic) return name;

    var buffer = StringBuffer(name);
    if (detail.showVersion ?? _showVersionConstraint) {
      buffer.write(' $constraint');
    }

    if (!isRoot && (detail.showSource ?? source is! HostedSource)) {
      buffer.write(' from $source');
      if (detail.showDescription) {
        buffer.write(' ${source.formatDescription(description)}');
      }
    }

    if (detail.showFeatures && features.isNotEmpty) {
      buffer.write(' $featureDescription');
    }

    return buffer.toString();
  }

  /// Whether to include the version constraint in [toString] by default.
  bool get _showVersionConstraint {
    if (isRoot) return false;
    if (!constraint.isAny) return true;
    if (source is PathSource) return false;
    if (source is GitSource) return false;
    return true;
  }

  /// Returns a new [PackageRange] with [features] merged with [this.features].
  PackageRange withFeatures(Map<String, FeatureDependency> features) {
    if (features.isEmpty) return this;
    return PackageRange(name, source, constraint, description,
        features: Map.from(this.features)..addAll(features));
  }

  /// Returns a copy of [this] with the same semantics, but with a `^`-style
  /// constraint if possible.
  PackageRange withTerseConstraint() {
    if (constraint is! VersionRange) return this;
    if (constraint.toString().startsWith('^')) return this;

    var range = constraint as VersionRange;
    if (!range.includeMin) return this;
    if (range.includeMax) return this;
    if (range.min == null) return this;
    if (range.max == range.min.nextBreaking.firstPreRelease ||
        (range.min.isPreRelease && range.max == range.min.nextBreaking)) {
      return withConstraint(VersionConstraint.compatibleWith(range.min));
    } else {
      return this;
    }
  }

  /// Whether [id] satisfies this dependency.
  ///
  /// Specifically, whether [id] refers to the same package as [this] *and*
  /// [constraint] allows `id.version`.
  bool allows(PackageId id) => samePackage(id) && constraint.allows(id.version);

  @override
  int get hashCode =>
      super.hashCode ^ constraint.hashCode ^ _featureEquality.hash(features);

  @override
  bool operator ==(other) =>
      other is PackageRange &&
      samePackage(other) &&
      other.constraint == constraint &&
      _featureEquality.equals(other.features, features);
}

/// An enum of types of dependencies on a [Feature].
class FeatureDependency {
  /// The feature must exist and be enabled for this dependency to be satisfied.
  static const required = FeatureDependency._('required');

  /// The feature must be enabled if it exists, but is not required to exist for
  /// this dependency to be satisfied.
  static const ifAvailable = FeatureDependency._('if available');

  /// The feature is neither required to exist nor to be enabled for this
  /// feature to be satisfied.
  static const unused = FeatureDependency._('unused');

  final String _name;

  /// Whether this type of dependency enables the feature it depends on.
  bool get isEnabled => this != unused;

  const FeatureDependency._(this._name);

  @override
  String toString() => _name;
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
  final bool showVersion;

  /// Whether to show the package source.
  ///
  /// If this is `null`, the source is shown for all non-hosted, non-root
  /// packages. It's always `true` if [showDescription] is `true`.
  final bool showSource;

  /// Whether to show the package description.
  ///
  /// This defaults to `false`.
  final bool showDescription;

  /// Whether to show the package features.
  ///
  /// This defaults to `true`.
  final bool showFeatures;

  const PackageDetail(
      {this.showVersion,
      bool showSource,
      bool showDescription,
      bool showFeatures})
      : showSource = showDescription == true ? true : showSource,
        showDescription = showDescription ?? false,
        showFeatures = showFeatures ?? true;

  /// Returns a [PackageDetail] with the maximum amount of detail between [this]
  /// and [other].
  PackageDetail max(PackageDetail other) => PackageDetail(
      showVersion: showVersion || other.showVersion,
      showSource: showSource || other.showSource,
      showDescription: showDescription || other.showDescription,
      showFeatures: showFeatures || other.showFeatures);
}
