// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart' hide mapMap;
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'io.dart';
import 'language_version.dart';
import 'package_name.dart';
import 'pubspec_parse.dart';
import 'sdk.dart';
import 'system_cache.dart';

export 'pubspec_parse.dart' hide PubspecBase;

/// The default SDK upper bound constraint for packages that don't declare one.
///
/// This provides a sane default for packages that don't have an upper bound.
final VersionRange _defaultUpperBoundSdkConstraint =
    VersionConstraint.parse('<2.0.0') as VersionRange;

/// The parsed contents of a pubspec file.
///
/// The fields of a pubspec are, for the most part, validated when they're first
/// accessed. This allows a partially-invalid pubspec to be used if only the
/// valid portions are relevant. To get a list of all errors in the pubspec, use
/// [allErrors].
class Pubspec extends PubspecBase {
  // If a new lazily-initialized field is added to this class and the
  // initialization can throw a [PubspecException], that error should also be
  // exposed through [allErrors].

  /// The fields of [pubspecOverridesFilename]. `null` if no such file exists or has
  /// to be considered.
  final YamlMap? _overridesFileFields;

  String? get _packageName => fields['name'] != null ? name : null;

  final bool dependencyOverridesFromOverridesFile;

  /// The name of the manifest file.
  static const pubspecYamlFilename = 'pubspec.yaml';

  /// The filename of the pubspec overrides file.
  ///
  /// This file can contain dependency_overrides that override those in
  /// pubspec.yaml.
  static const pubspecOverridesFilename = 'pubspec_overrides.yaml';

  /// The registry of sources to use when parsing [dependencies] and
  /// [devDependencies].
  ///
  /// This will be null if this was created using [Pubspec] or [Pubspec.empty].
  final SourceRegistry _sources;

  /// The location from which the pubspec was loaded.
  ///
  /// This can be null if the pubspec was created in-memory or if its location
  /// is unknown.
  Uri? get _location => fields.span.sourceUrl;

  /// The additional packages this package depends on.
  Map<String, PackageRange> get dependencies =>
      _dependencies ??= _parseDependencies(
        'dependencies',
        fields.nodes['dependencies'],
        _sources,
        languageVersion,
        _packageName,
        _location,
      );

  Map<String, PackageRange>? _dependencies;

  /// The packages this package depends on when it is the root package.
  Map<String, PackageRange> get devDependencies =>
      _devDependencies ??= _parseDependencies(
        'dev_dependencies',
        fields.nodes['dev_dependencies'],
        _sources,
        languageVersion,
        _packageName,
        _location,
      );

  Map<String, PackageRange>? _devDependencies;

  /// The dependency constraints that this package overrides when it is the
  /// root package.
  ///
  /// Dependencies here will replace any dependency on a package with the same
  /// name anywhere in the dependency graph.
  ///
  /// These can occur both in the pubspec.yaml file and the [pubspecOverridesFilename].
  Map<String, PackageRange> get dependencyOverrides {
    if (_dependencyOverrides != null) return _dependencyOverrides!;
    final pubspecOverridesFields = _overridesFileFields;
    if (pubspecOverridesFields != null) {
      pubspecOverridesFields.nodes.forEach((key, _) {
        if (!const {'dependency_overrides'}.contains(key.value)) {
          throw SourceSpanApplicationException(
            'pubspec_overrides.yaml only supports the `dependency_overrides` field.',
            (key as YamlNode).span,
          );
        }
      });
      if (pubspecOverridesFields.containsKey('dependency_overrides')) {
        _dependencyOverrides = _parseDependencies(
          'dependency_overrides',
          pubspecOverridesFields.nodes['dependency_overrides'],
          _sources,
          languageVersion,
          _packageName,
          _location,
          fileType: _FileType.pubspecOverrides,
        );
      }
    }
    return _dependencyOverrides ??= _parseDependencies(
      'dependency_overrides',
      fields.nodes['dependency_overrides'],
      _sources,
      languageVersion,
      _packageName,
      _location,
    );
  }

  Map<String, PackageRange>? _dependencyOverrides;

  SdkConstraint get dartSdkConstraint => sdkConstraints['dart']!;

  /// A map from SDK identifiers to constraints on those SDK versions.
  late final Map<String, SdkConstraint> sdkConstraints =
      _givenSdkConstraints ?? UnmodifiableMapView(_parseEnvironment(fields));

  final Map<String, SdkConstraint>? _givenSdkConstraints;

  /// Whether or not to apply the [_defaultUpperBoundsSdkConstraint] to this
  /// pubspec.
  final bool _includeDefaultSdkConstraint;

  /// Parses the "environment" field in [parent] and returns a map from SDK
  /// identifiers to constraints on those SDKs.
  Map<String, SdkConstraint> _parseEnvironment(YamlMap parent) {
    var yaml = parent['environment'];
    final VersionConstraint originalDartSdkConstraint;
    if (yaml == null) {
      originalDartSdkConstraint = VersionConstraint.any;
    } else if (yaml is! YamlMap) {
      _error(
        '"environment" field must be a map.',
        parent.nodes['environment']!.span,
      );
    } else {
      originalDartSdkConstraint = _parseVersionConstraint(
        yaml.nodes['sdk'],
        _packageName,
        _FileType.pubspec,
      );
    }
    var constraints = {
      'dart': SdkConstraint.interpretDartSdkConstraint(
        originalDartSdkConstraint,
        defaultUpperBoundConstraint: _includeDefaultSdkConstraint
            ? _defaultUpperBoundSdkConstraint
            : null,
      )
    };

    if (yaml is YamlMap) {
      yaml.nodes.forEach((nameNode, constraintNode) {
        final name = nameNode.value;
        if (name is! String) {
          _error('SDK names must be strings.', (nameNode as YamlNode).span);
        } else if (name == 'dart') {
          _error(
            'Use "sdk" to for Dart SDK constraints.',
            (nameNode as YamlNode).span,
          );
        }
        if (name == 'sdk') return;

        final constraint = _parseVersionConstraint(
          constraintNode,
          _packageName,
          _FileType.pubspec,
        );
        constraints[name] = name == 'flutter'
            ? SdkConstraint.interpretFlutterSdkConstraint(constraint)
            : SdkConstraint(constraint);
      });
    }
    return constraints;
  }

  /// The language version implied by the sdk constraint.
  LanguageVersion get languageVersion {
    return LanguageVersion.fromSdkConstraint(
      dartSdkConstraint.originalConstraint,
    );
  }

  /// Loads the pubspec for a package located in [packageDir].
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [SourceSpanApplicationException].
  ///
  /// If [allowOverridesFile] is `true` [pubspecOverridesFilename] is loaded and
  /// is allowed to override dependency_overrides from `pubspec.yaml`.
  factory Pubspec.load(
    String packageDir,
    SourceRegistry sources, {
    String? expectedName,
    bool allowOverridesFile = false,
  }) {
    var pubspecPath = path.join(packageDir, pubspecYamlFilename);
    var overridesPath = path.join(packageDir, pubspecOverridesFilename);
    if (!fileExists(pubspecPath)) {
      throw FileException(
        // Make the package dir absolute because for the entrypoint it'll just
        // be ".", which may be confusing.
        'Could not find a file named "pubspec.yaml" in '
        '"${canonicalize(packageDir)}".',
        pubspecPath,
      );
    }
    String? overridesFileContents =
        allowOverridesFile && fileExists(overridesPath)
            ? readTextFile(overridesPath)
            : null;

    return Pubspec.parse(
      readTextFile(pubspecPath),
      sources,
      expectedName: expectedName,
      location: path.toUri(pubspecPath),
      overridesFileContents: overridesFileContents,
      overridesLocation: path.toUri(overridesPath),
    );
  }

  Pubspec(
    String name, {
    Version? version,
    Iterable<PackageRange>? dependencies,
    Iterable<PackageRange>? devDependencies,
    Iterable<PackageRange>? dependencyOverrides,
    Map? fields,
    SourceRegistry? sources,
    Map<String, SdkConstraint>? sdkConstraints,
    this.dependencyOverridesFromOverridesFile = false,
  })  : _dependencies = dependencies == null
            ? null
            : Map.fromIterable(
                dependencies,
                key: (range) => (range as PackageRange).name,
              ),
        _devDependencies = devDependencies == null
            ? null
            : Map.fromIterable(
                devDependencies,
                key: (range) => (range as PackageRange).name,
              ),
        _dependencyOverrides = dependencyOverrides == null
            ? null
            : Map.fromIterable(
                dependencyOverrides,
                key: (range) => (range as PackageRange).name,
              ),
        _givenSdkConstraints = sdkConstraints ??
            UnmodifiableMapView({'dart': SdkConstraint(VersionConstraint.any)}),
        _includeDefaultSdkConstraint = false,
        _sources = sources ??
            ((String? name) => throw StateError('No source registry given')),
        _overridesFileFields = null,
        super(
          fields == null ? YamlMap() : YamlMap.wrap(fields),
          name: name,
          version: version,
        );

  /// Returns a Pubspec object for an already-parsed map representing its
  /// contents.
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [PubspecError].
  ///
  /// [location] is the location from which this pubspec was loaded.
  Pubspec.fromMap(
    Map fields,
    this._sources, {
    YamlMap? overridesFields,
    String? expectedName,
    Uri? location,
  })  : _overridesFileFields = overridesFields,
        _includeDefaultSdkConstraint = true,
        _givenSdkConstraints = null,
        dependencyOverridesFromOverridesFile = overridesFields != null &&
            overridesFields.containsKey('dependency_overrides'),
        super(
          fields is YamlMap
              ? fields
              : YamlMap.wrap(fields, sourceUrl: location),
        ) {
    // If [expectedName] is passed, ensure that the actual 'name' field exists
    // and matches the expectation.
    if (expectedName == null) return;
    if (name == expectedName) return;

    throw SourceSpanApplicationException(
      '"name" field doesn\'t match expected name '
      '"$expectedName".',
      this.fields.nodes['name']!.span,
    );
  }

  /// Parses the pubspec stored at [location] whose text is [contents].
  ///
  /// If the pubspec doesn't define a version for itself, it defaults to
  /// [Version.none].
  factory Pubspec.parse(
    String contents,
    SourceRegistry sources, {
    String? expectedName,
    Uri? location,
    String? overridesFileContents,
    Uri? overridesLocation,
  }) {
    late final YamlMap pubspecMap;
    YamlMap? overridesFileMap;
    try {
      pubspecMap = _ensureMap(loadYamlNode(contents, sourceUrl: location));
      if (overridesFileContents != null) {
        overridesFileMap = _ensureMap(
          loadYamlNode(overridesFileContents, sourceUrl: overridesLocation),
        );
      }
    } on YamlException catch (error) {
      throw SourceSpanApplicationException(error.message, error.span);
    }

    return Pubspec.fromMap(
      pubspecMap,
      sources,
      overridesFields: overridesFileMap,
      expectedName: expectedName,
      location: location,
    );
  }

  /// Ensures that [node] is a mapping.
  ///
  /// If [node] is already a map it is returned.
  /// If [node] is yaml-null an empty map is returned.
  /// Otherwise an exception is thrown.
  static YamlMap _ensureMap(YamlNode node) {
    if (node is YamlScalar && node.value == null) {
      return YamlMap(sourceUrl: node.span.sourceUrl);
    } else if (node is YamlMap) {
      return node;
    } else {
      throw SourceSpanApplicationException(
        'The pubspec must be a YAML mapping.',
        node.span,
      );
    }
  }

  /// Returns a list of most errors in this pubspec.
  ///
  /// This will return at most one error for each field.
  List<SourceSpanApplicationException> get allErrors {
    var errors = <SourceSpanApplicationException>[];
    void collectError(void Function() fn) {
      try {
        fn();
      } on SourceSpanApplicationException catch (e) {
        errors.add(e);
      }
    }

    collectError(() => name);
    collectError(() => version);
    collectError(() => dependencies);
    collectError(() => devDependencies);
    collectError(() => publishTo);
    collectError(() => executables);
    collectError(() => falseSecrets);
    collectError(() => sdkConstraints);
    return errors;
  }

  /// Returns the type of dependency from this package onto [name].
  DependencyType dependencyType(String? name) {
    if (dependencies.containsKey(name)) {
      return DependencyType.direct;
    } else if (devDependencies.containsKey(name)) {
      return DependencyType.dev;
    } else {
      return DependencyType.none;
    }
  }
}

/// The type of dependency from one package to another.
enum DependencyType {
  direct,
  dev,
  none;

  @override
  String toString() => name;
}

/// Parses the dependency field named [field], and returns the corresponding
/// map of dependency names to dependencies.
Map<String, PackageRange> _parseDependencies(
  String field,
  YamlNode? node,
  SourceRegistry sources,
  LanguageVersion languageVersion,
  String? packageName,
  Uri? location, {
  _FileType fileType = _FileType.pubspec,
}) {
  var dependencies = <String, PackageRange>{};

  // Allow an empty dependencies key.
  if (node == null || node.value == null) return dependencies;

  if (node is! YamlMap) {
    _error('"$field" field must be a map.', node.span);
  }

  var nonStringNode =
      node.nodes.keys.firstWhere((e) => e.value is! String, orElse: () => null);
  if (nonStringNode != null) {
    _error(
      'A dependency name must be a string.',
      (nonStringNode as YamlNode).span,
    );
  }

  node.nodes.forEach(
    (nameNode, specNode) {
      var name = nameNode.value as String;
      var spec = specNode.value;
      if (packageName != null && name == packageName) {
        _error(
          'A package may not list itself as a dependency.',
          (nameNode as YamlNode).span,
        );
      }

      YamlNode? descriptionNode;
      String? sourceName;

      VersionConstraint versionConstraint = VersionRange();
      if (spec == null) {
        sourceName = null;
      } else if (spec is String) {
        sourceName = null;
        versionConstraint =
            _parseVersionConstraint(specNode, packageName, fileType);
      } else if (spec is Map) {
        // Don't write to the immutable YAML map.
        spec = Map.from(spec);
        var specMap = specNode as YamlMap;

        if (spec.containsKey('version')) {
          spec.remove('version');
          versionConstraint = _parseVersionConstraint(
            specMap.nodes['version'],
            packageName,
            fileType,
          );
        }

        var sourceNames = spec.keys.toList();
        if (sourceNames.length > 1) {
          _error('A dependency may only have one source.', specNode.span);
        } else if (sourceNames.isEmpty) {
          // Default to a hosted dependency if no source is specified.
          sourceName = 'hosted';
        }

        if (sourceName == null) {
          if (sourceNames.single is! String) {
            _error(
              'A source name must be a string.',
              (specMap.nodes.keys.single as YamlNode).span,
            );
          }
          sourceName = sourceNames.single as String;
        }

        descriptionNode ??= specMap.nodes[sourceName];
      } else {
        _error(
          'A dependency specification must be a string or a mapping.',
          specNode.span,
        );
      }

      // Let the source validate the description.
      var ref = _wrapFormatException(
        'description',
        descriptionNode?.span,
        () {
          String? pubspecDir;
          if (location != null && _isFileUri(location)) {
            pubspecDir = path.dirname(path.fromUri(location));
          }

          return sources(sourceName).parseRef(
            name,
            descriptionNode?.value,
            containingDir: pubspecDir,
            languageVersion: languageVersion,
          );
        },
        packageName,
        fileType,
        targetPackage: name,
      );

      dependencies[name] = ref.withConstraint(versionConstraint);
    },
  );

  return dependencies;
}

/// Returns whether [uri] is a file URI.
///
/// This is slightly more complicated than just checking if the scheme is
/// 'file', since relative URIs also refer to the filesystem on the VM.
bool _isFileUri(Uri uri) => uri.scheme == 'file' || uri.scheme == '';

/// Parses [node] to a [VersionConstraint].
///
/// If or [defaultUpperBoundConstraint] is specified then it will be set as the
/// max constraint if the original constraint doesn't have an upper bound and it
/// is compatible with [defaultUpperBoundConstraint].
VersionConstraint _parseVersionConstraint(
  YamlNode? node,
  String? packageName,
  _FileType fileType,
) {
  if (node?.value == null) {
    return VersionConstraint.any;
  }
  if (node!.value is! String) {
    _error('A version constraint must be a string.', node.span);
  }

  return _wrapFormatException(
    'version constraint',
    node.span,
    () {
      var constraint = VersionConstraint.parse(node.value as String);
      return constraint;
    },
    packageName,
    fileType,
  );
}

/// Runs [fn] and wraps any [FormatException] it throws in a
/// [SourceSpanApplicationException].
///
/// [description] should be a noun phrase that describes whatever's being
/// parsed or processed by [fn]. [span] should be the location of whatever's
/// being processed within the pubspec.
///
/// If [targetPackage] is provided, the value is used to describe the
/// dependency that caused the problem.
T _wrapFormatException<T>(
  String description,
  SourceSpan? span,
  T Function() fn,
  String? packageName,
  _FileType fileType, {
  String? targetPackage,
}) {
  try {
    return fn();
  } on FormatException catch (e) {
    // If we already have a pub exception with a span, re-use that
    if (e is SourceSpanApplicationException) rethrow;

    var msg = 'Invalid $description';
    final typeName = _fileTypeName(fileType);
    if (targetPackage != null) {
      msg = '$msg in the "$packageName" $typeName on the "$targetPackage" '
          'dependency';
    }
    msg = '$msg: ${e.message}';
    _error(msg, span);
  }
}

/// Throws a [SourceSpanApplicationException] with the given message.
Never _error(String message, SourceSpan? span) {
  throw SourceSpanApplicationException(message, span);
}

enum _FileType {
  pubspec,
  pubspecOverrides,
}

String _fileTypeName(_FileType type) {
  switch (type) {
    case _FileType.pubspec:
      return 'pubspec';
    case _FileType.pubspecOverrides:
      return 'pubspec override';
  }
}

/// There are special rules or interpreting SDK constraints, we take care to
/// save the original constraint as found in pubspec.yaml.
class SdkConstraint {
  /// The constraint as written in the pubspec.yaml.
  final VersionConstraint originalConstraint;

  /// The constraint as interpreted by pub.
  final VersionConstraint effectiveConstraint;

  SdkConstraint(
    this.effectiveConstraint, {
    VersionConstraint? originalConstraint,
  }) : originalConstraint = originalConstraint ?? effectiveConstraint;

  /// Implement support for down to 2.12 in the dart 3 series. Note that this
  /// function has to be be idempotent, because we apply it both when we write
  /// and read lock-file constraints, so applying this function a second time
  /// should have no further effect.
  factory SdkConstraint.interpretDartSdkConstraint(
    VersionConstraint originalConstraint, {
    required VersionConstraint? defaultUpperBoundConstraint,
  }) {
    VersionConstraint constraint = originalConstraint;
    if (defaultUpperBoundConstraint != null &&
        constraint is VersionRange &&
        constraint.max == null &&
        defaultUpperBoundConstraint.allowsAny(constraint)) {
      constraint = VersionConstraint.intersection(
        [constraint, defaultUpperBoundConstraint],
      );
    }
    // If a package is null safe it should also be compatible with dart 3.
    // Therefore we rewrite a null-safety enabled constraint with the upper
    // bound <3.0.0 to be have upper bound <4.0.0
    //
    // Only do this rewrite after dart 3.
    if (sdk.version.major >= 3 &&
        constraint is VersionRange &&
        LanguageVersion.fromSdkConstraint(constraint) >=
            LanguageVersion.firstVersionWithNullSafety &&
        // <3.0.0 is parsed into a max of 3.0.0-0, so that is what we look for
        // here.
        constraint.max == Version(3, 0, 0).firstPreRelease &&
        constraint.includeMax == false) {
      constraint = VersionRange(
        min: constraint.min,
        includeMin: constraint.includeMin,
        // We don't have to use .firstPreRelease as the constructor will do that
        // if needed.
        max: Version(4, 0, 0),
      );
    }
    return SdkConstraint(constraint, originalConstraint: originalConstraint);
  }

  // Flutter constraints get special treatment, as Flutter won't be using
  // semantic versioning to mark breaking releases. We simply ignore upper
  // bounds.
  factory SdkConstraint.interpretFlutterSdkConstraint(
    VersionConstraint constraint,
  ) {
    if (constraint is VersionRange) {
      return SdkConstraint(
        VersionRange(min: constraint.min, includeMin: constraint.includeMin),
        originalConstraint: constraint,
      );
    }
    return SdkConstraint(constraint);
  }

  /// The language version of a constraint is determined from how it is written.
  LanguageVersion get languageVersion =>
      LanguageVersion.fromSdkConstraint(originalConstraint);

  // We currently don't call this anywhere - so this is only for debugging
  // purposes.
  @override
  String toString() {
    if (effectiveConstraint != originalConstraint) {
      return '$originalConstraint (interpreted as $effectiveConstraint)';
    }
    return effectiveConstraint.toString();
  }

  @override
  operator ==(other) =>
      other is SdkConstraint &&
      other.effectiveConstraint == effectiveConstraint &&
      other.originalConstraint == originalConstraint;

  @override
  int get hashCode => Object.hash(effectiveConstraint, originalConstraint);
}
