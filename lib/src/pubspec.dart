// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:collection/collection.dart' hide mapMap;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'feature.dart';
import 'io.dart';
import 'language_version.dart';
import 'package_name.dart';
import 'pubspec_parse.dart';
import 'source_registry.dart';
import 'utils.dart';

export 'pubspec_parse.dart' hide PubspecBase;

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

  /// The registry of sources to use when parsing [dependencies] and
  /// [devDependencies].
  ///
  /// This will be null if this was created using [new Pubspec] or [new
  /// Pubspec.empty].
  final SourceRegistry _sources;

  /// The location from which the pubspec was loaded.
  ///
  /// This can be null if the pubspec was created in-memory or if its location
  /// is unknown.
  Uri get _location => fields.span.sourceUrl;

  /// The additional packages this package depends on.
  Map<String, PackageRange> get dependencies {
    if (_dependencies != null) return _dependencies;
    _dependencies =
        _parseDependencies('dependencies', fields.nodes['dependencies']);
    return _dependencies;
  }

  Map<String, PackageRange> _dependencies;

  /// The packages this package depends on when it is the root package.
  Map<String, PackageRange> get devDependencies {
    if (_devDependencies != null) return _devDependencies;
    _devDependencies = _parseDependencies(
        'dev_dependencies', fields.nodes['dev_dependencies']);
    return _devDependencies;
  }

  Map<String, PackageRange> _devDependencies;

  /// The dependency constraints that this package overrides when it is the
  /// root package.
  ///
  /// Dependencies here will replace any dependency on a package with the same
  /// name anywhere in the dependency graph.
  Map<String, PackageRange> get dependencyOverrides {
    if (_dependencyOverrides != null) return _dependencyOverrides;
    _dependencyOverrides = _parseDependencies(
        'dependency_overrides', fields.nodes['dependency_overrides']);
    return _dependencyOverrides;
  }

  Map<String, PackageRange> _dependencyOverrides;

  Map<String, Feature> get features {
    if (_features != null) return _features;
    var features = fields['features'];
    if (features == null) {
      _features = const {};
      return _features;
    }

    if (features is! Map) {
      _error('"features" field must be a map.', fields.nodes['features'].span);
    }

    _features = mapMap(features.nodes,
        key: (nameNode, _) => _validateFeatureName(nameNode),
        value: (nameNode, specNode) {
          if (specNode.value == null) {
            return Feature(nameNode.value, const []);
          }

          if (specNode is! Map) {
            _error('A feature specification must be a map.', specNode.span);
          }

          var onByDefault = specNode['default'] ?? true;
          if (onByDefault is! bool) {
            _error('Default must be true or false.',
                specNode.nodes['default'].span);
          }

          var requires = _parseStringList(specNode.nodes['requires'],
              validate: (name, span) {
            if (!features.containsKey(name)) _error('Undefined feature.', span);
          });

          var dependencies = _parseDependencies(
              'dependencies', specNode.nodes['dependencies']);

          var sdkConstraints = parseEnvironment(specNode);

          return Feature(nameNode.value, dependencies.values,
              requires: requires,
              sdkConstraints: sdkConstraints,
              onByDefault: onByDefault);
        });
    return _features;
  }

  Map<String, Feature> _features;

  /// Whether or not the pubspec has no contents.
  bool get isEmpty =>
      name == null && version == Version.none && dependencies.isEmpty;

  /// The language version implied by the sdk constraint.
  LanguageVersion get languageVersion =>
      LanguageVersion.fromSdkConstraint(originalDartSdkConstraint);

  /// Loads the pubspec for a package located in [packageDir].
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [PubspecException].
  factory Pubspec.load(String packageDir, SourceRegistry sources,
      {String expectedName}) {
    var pubspecPath = path.join(packageDir, 'pubspec.yaml');
    var pubspecUri = path.toUri(pubspecPath);
    if (!fileExists(pubspecPath)) {
      throw FileException(
          // Make the package dir absolute because for the entrypoint it'll just
          // be ".", which may be confusing.
          'Could not find a file named "pubspec.yaml" in '
          '"${canonicalize(packageDir)}".',
          pubspecPath);
    }

    return Pubspec.parse(readTextFile(pubspecPath), sources,
        expectedName: expectedName, location: pubspecUri);
  }

  Pubspec(String name,
      {Version version,
      Iterable<PackageRange> dependencies,
      Iterable<PackageRange> devDependencies,
      Iterable<PackageRange> dependencyOverrides,
      Map fields,
      SourceRegistry sources,
      Map<String, VersionConstraint> sdkConstraints})
      : _dependencies = dependencies == null
            ? null
            : Map.fromIterable(dependencies, key: (range) => range.name),
        _devDependencies = devDependencies == null
            ? null
            : Map.fromIterable(devDependencies, key: (range) => range.name),
        _dependencyOverrides = dependencyOverrides == null
            ? null
            : Map.fromIterable(dependencyOverrides, key: (range) => range.name),
        _sources = sources,
        super(
          fields == null ? YamlMap() : YamlMap.wrap(fields),
          name: name,
          version: version,
          sdkConstraints: sdkConstraints ??
              UnmodifiableMapView({'dart': VersionConstraint.any}),
        );

  Pubspec.empty()
      : _sources = null,
        _dependencies = {},
        _devDependencies = {},
        super(
          YamlMap(),
          version: Version.none,
          sdkConstraints: {'dart': VersionConstraint.any},
        );

  /// Returns a Pubspec object for an already-parsed map representing its
  /// contents.
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [PubspecError].
  ///
  /// [location] is the location from which this pubspec was loaded.
  Pubspec.fromMap(Map fields, this._sources,
      {String expectedName, Uri location})
      : super(
          fields is YamlMap
              ? fields
              : YamlMap.wrap(fields, sourceUrl: location),
          includeDefaultSdkConstraint: true,
        ) {
    // If [expectedName] is passed, ensure that the actual 'name' field exists
    // and matches the expectation.
    if (expectedName == null) return;
    if (name == expectedName) return;

    throw PubspecException(
        '"name" field doesn\'t match expected name '
        '"$expectedName".',
        this.fields.nodes['name'].span);
  }

  /// Parses the pubspec stored at [filePath] whose text is [contents].
  ///
  /// If the pubspec doesn't define a version for itself, it defaults to
  /// [Version.none].
  factory Pubspec.parse(String contents, SourceRegistry sources,
      {String expectedName, Uri location}) {
    YamlNode pubspecNode;
    try {
      pubspecNode = loadYamlNode(contents, sourceUrl: location);
    } on YamlException catch (error) {
      throw PubspecException(error.message, error.span);
    }

    Map pubspecMap;
    if (pubspecNode is YamlScalar && pubspecNode.value == null) {
      pubspecMap = YamlMap(sourceUrl: location);
    } else if (pubspecNode is YamlMap) {
      pubspecMap = pubspecNode;
    } else {
      throw PubspecException(
          'The pubspec must be a YAML mapping.', pubspecNode.span);
    }

    return Pubspec.fromMap(pubspecMap, sources,
        expectedName: expectedName, location: location);
  }

  /// Returns a list of most errors in this pubspec.
  ///
  /// This will return at most one error for each field.
  List<PubspecException> get allErrors {
    var errors = <PubspecException>[];
    void _collectError(void Function() fn) {
      try {
        fn();
      } on PubspecException catch (e) {
        errors.add(e);
      }
    }

    _collectError(() => name);
    _collectError(() => version);
    _collectError(() => dependencies);
    _collectError(() => devDependencies);
    _collectError(() => publishTo);
    _collectError(() => features);
    _collectError(() => executables);
    _collectError(() => falseSecrets);
    _collectError(ensureEnvironment);
    return errors;
  }

  /// Parses the dependency field named [field], and returns the corresponding
  /// map of dependency names to dependencies.
  Map<String, PackageRange> _parseDependencies(String field, YamlNode node) {
    var dependencies = <String, PackageRange>{};

    // Allow an empty dependencies key.
    if (node == null || node.value == null) return dependencies;

    if (node is! YamlMap) {
      _error('"$field" field must be a map.', node.span);
    }

    var map = node as YamlMap;
    var nonStringNode = map.nodes.keys
        .firstWhere((e) => e.value is! String, orElse: () => null);
    if (nonStringNode != null) {
      _error('A dependency name must be a string.', nonStringNode.span);
    }

    map.nodes.forEach((nameNode, specNode) {
      var name = nameNode.value;
      var spec = specNode.value;
      if (fields['name'] != null && name == this.name) {
        _error('A package may not list itself as a dependency.', nameNode.span);
      }

      YamlNode descriptionNode;
      String sourceName;

      VersionConstraint versionConstraint = VersionRange();
      var features = const <String, FeatureDependency>{};
      if (spec == null) {
        descriptionNode = nameNode;
        sourceName = _sources.defaultSource.name;
      } else if (spec is String) {
        descriptionNode = nameNode;
        sourceName = _sources.defaultSource.name;
        versionConstraint = parseVersionConstraint(specNode);
      } else if (spec is Map) {
        // Don't write to the immutable YAML map.
        spec = Map.from(spec);
        var specMap = specNode as YamlMap;

        if (spec.containsKey('version')) {
          spec.remove('version');
          versionConstraint = parseVersionConstraint(specMap.nodes['version']);
        }

        if (spec.containsKey('features')) {
          spec.remove('features');
          features = _parseDependencyFeatures(specMap.nodes['features']);
        }

        var sourceNames = spec.keys.toList();
        if (sourceNames.length > 1) {
          _error('A dependency may only have one source.', specNode.span);
        } else if (sourceNames.isEmpty) {
          // Default to a hosted dependency if no source is specified.
          sourceName = 'hosted';
          descriptionNode = nameNode;
        }

        sourceName ??= sourceNames.single;
        if (sourceName is! String) {
          _error('A source name must be a string.',
              specMap.nodes.keys.single.span);
        }

        descriptionNode ??= specMap.nodes[sourceName];
      } else {
        _error('A dependency specification must be a string or a mapping.',
            specNode.span);
      }

      // Let the source validate the description.
      var ref = _wrapFormatException('description', descriptionNode?.span, () {
        String pubspecPath;
        if (_location != null && _isFileUri(_location)) {
          pubspecPath = path.fromUri(_location);
        }

        return _sources[sourceName].parseRef(name, descriptionNode?.value,
            containingPath: pubspecPath);
      }, targetPackage: name);

      dependencies[name] =
          ref.withConstraint(versionConstraint).withFeatures(features);
    });

    return dependencies;
  }

  /// Parses [node] to a map from feature names to whether those features are
  /// enabled.
  Map<String, FeatureDependency> _parseDependencyFeatures(YamlNode node) {
    if (node?.value == null) return const {};
    if (node is! YamlMap) _error('Features must be a map.', node.span);

    return mapMap((node as YamlMap).nodes,
        key: (nameNode, _) => _validateFeatureName(nameNode),
        value: (_, valueNode) {
          var value = valueNode.value;
          if (value is bool) {
            return value
                ? FeatureDependency.required
                : FeatureDependency.unused;
          } else if (value is String && value == 'if available') {
            return FeatureDependency.ifAvailable;
          } else {
            _error('Features must be true, false, or "if available".',
                valueNode.span);
          }
        });
  }

  /// Verifies that [node] is a string and a valid feature name, and returns it
  /// if so.
  String _validateFeatureName(YamlNode node) {
    var name = node.value;
    if (name is! String) {
      _error('A feature name must be a string.', node.span);
    } else if (!packageNameRegExp.hasMatch(name)) {
      _error('A feature name must be a valid Dart identifier.', node.span);
    }

    return name;
  }

  /// Verifies that [node] is a list of strings and returns it.
  ///
  /// If [validate] is passed, it's called for each string in [node].
  List<String> _parseStringList(YamlNode node,
      {void Function(String value, SourceSpan) validate}) {
    var list = _parseList(node);
    for (var element in list.nodes) {
      var value = element.value;
      if (value is String) {
        if (validate != null) validate(value, element.span);
      } else {
        _error('Must be a string.', element.span);
      }
    }
    return list.cast<String>();
  }

  /// Verifies that [node] is a list and returns it.
  YamlList _parseList(YamlNode node) {
    if (node == null || node.value == null) return YamlList();
    if (node is YamlList) return node;
    _error('Must be a list.', node.span);
  }

  /// Runs [fn] and wraps any [FormatException] it throws in a
  /// [PubspecException].
  ///
  /// [description] should be a noun phrase that describes whatever's being
  /// parsed or processed by [fn]. [span] should be the location of whatever's
  /// being processed within the pubspec.
  ///
  /// If [targetPackage] is provided, the value is used to describe the
  /// dependency that caused the problem.
  T _wrapFormatException<T>(
      String description, SourceSpan span, T Function() fn,
      {String targetPackage}) {
    try {
      return fn();
    } on FormatException catch (e) {
      var msg = 'Invalid $description';
      if (targetPackage != null) {
        msg = '$msg in the "$name" pubspec on the "$targetPackage" dependency';
      }
      msg = '$msg: ${e.message}';
      _error(msg, span);
    }
  }

  /// Throws a [PubspecException] with the given message.
  @alwaysThrows
  void _error(String message, SourceSpan span) {
    throw PubspecException(message, span);
  }
}

/// Returns whether [uri] is a file URI.
///
/// This is slightly more complicated than just checking if the scheme is
/// 'file', since relative URIs also refer to the filesystem on the VM.
bool _isFileUri(Uri uri) => uri.scheme == 'file' || uri.scheme == '';
