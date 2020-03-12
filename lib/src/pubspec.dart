// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'feature.dart';
import 'io.dart';
import 'log.dart';
import 'package_name.dart';
import 'sdk.dart';
import 'source_registry.dart';
import 'utils.dart';

/// A regular expression matching allowed package names.
///
/// This allows dot-separated valid Dart identifiers. The dots are there for
/// compatibility with Google's internal Dart packages, but they may not be used
/// when publishing a package to pub.dartlang.org.
final _packageName =
    RegExp('^${identifierRegExp.pattern}(\\.${identifierRegExp.pattern})*\$');

/// The default SDK upper bound constraint for packages that don't declare one.
///
/// This provides a sane default for packages that don't have an upper bound.
final VersionRange _defaultUpperBoundSdkConstraint =
    VersionConstraint.parse('<2.0.0');

/// Whether or not to allow the pre-release SDK for packages that have an
/// upper bound Dart SDK constraint of <2.0.0.
///
/// If enabled then a Dart SDK upper bound of <2.0.0 is always converted to
/// <2.0.0-dev.infinity.
///
/// This has a default value of `true` but can be overridden with the
/// PUB_ALLOW_PRERELEASE_SDK system environment variable.
bool get _allowPreReleaseSdk => _allowPreReleaseSdkValue != 'false';

/// The value of the PUB_ALLOW_PRERELEASE_SDK environment variable, defaulted
/// to `true`.
final String _allowPreReleaseSdkValue = () {
  var value =
      Platform.environment['PUB_ALLOW_PRERELEASE_SDK']?.toLowerCase() ?? 'true';
  if (!['true', 'quiet', 'false'].contains(value)) {
    warning(yellow('''
The environment variable PUB_ALLOW_PRERELEASE_SDK is set as `$value`.
The expected value is either `true`, `quiet` (true but no logging), or `false`.
Using a default value of `true`.
'''));
    value = 'true';
  }
  return value;
}();

/// Whether or not to warn about pre-release SDK overrides.
bool get warnAboutPreReleaseSdkOverrides => _allowPreReleaseSdkValue != 'quiet';

/// The parsed contents of a pubspec file.
///
/// The fields of a pubspec are, for the most part, validated when they're first
/// accessed. This allows a partially-invalid pubspec to be used if only the
/// valid portions are relevant. To get a list of all errors in the pubspec, use
/// [allErrors].
class Pubspec {
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

  /// All pubspec fields.
  ///
  /// This includes the fields from which other properties are derived.
  final YamlMap fields;

  /// Whether or not to apply the [_defaultUpperBoundsSdkConstraint] to this
  /// pubspec.
  final bool _includeDefaultSdkConstraint;

  /// Whether or not the SDK version was overridden from <2.0.0 to
  /// <2.0.0-dev.infinity.
  bool get dartSdkWasOverridden => _dartSdkWasOverridden;
  bool _dartSdkWasOverridden = false;

  /// The package's name.
  String get name {
    if (_name != null) return _name;

    var name = fields['name'];
    if (name == null) {
      throw PubspecException('Missing the required "name" field.', fields.span);
    } else if (name is! String) {
      throw PubspecException(
          '"name" field must be a string.', fields.nodes['name'].span);
    } else if (!_packageName.hasMatch(name)) {
      throw PubspecException('"name" field must be a valid Dart identifier.',
          fields.nodes['name'].span);
    } else if (reservedWords.contains(name)) {
      throw PubspecException('"name" field may not be a Dart reserved word.',
          fields.nodes['name'].span);
    }

    _name = name;
    return _name;
  }

  String _name;

  /// The package's version.
  Version get version {
    if (_version != null) return _version;

    var version = fields['version'];
    if (version == null) {
      _version = Version.none;
      return _version;
    }

    var span = fields.nodes['version'].span;
    if (version is num) {
      var fixed = '$version.0';
      if (version is int) {
        fixed = '$fixed.0';
      }
      _error(
          '"version" field must have three numeric components: major, '
          'minor, and patch. Instead of "$version", consider "$fixed".',
          span);
    }
    if (version is! String) {
      _error('"version" field must be a string.', span);
    }

    _version = _wrapFormatException(
        'version number', span, () => Version.parse(version));
    return _version;
  }

  Version _version;

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

          var sdkConstraints = _parseEnvironment(specNode);

          return Feature(nameNode.value, dependencies.values,
              requires: requires,
              sdkConstraints: sdkConstraints,
              onByDefault: onByDefault);
        });
    return _features;
  }

  Map<String, Feature> _features;

  /// A map from SDK identifiers to constraints on those SDK versions.
  Map<String, VersionConstraint> get sdkConstraints {
    _ensureEnvironment();
    return _sdkConstraints;
  }

  Map<String, VersionConstraint> _sdkConstraints;

  /// The original Dart SDK constraint as written in the pubspec.
  ///
  /// If [dartSdkWasOverridden] is `false`, this will be identical to
  /// `sdkConstraints["dart"]`.
  VersionConstraint get originalDartSdkConstraint {
    _ensureEnvironment();
    return _originalDartSdkConstraint ?? sdkConstraints['dart'];
  }

  VersionConstraint _originalDartSdkConstraint;

  /// Ensures that the top-level "environment" field has been parsed and
  /// [_sdkConstraints] is set accordingly.
  void _ensureEnvironment() {
    if (_sdkConstraints != null) return;

    var sdkConstraints = _parseEnvironment(fields);
    var parsedDartSdkConstraint = sdkConstraints['dart'];

    if (parsedDartSdkConstraint is VersionRange &&
        _shouldEnableCurrentSdk(parsedDartSdkConstraint)) {
      _originalDartSdkConstraint = parsedDartSdkConstraint;
      _dartSdkWasOverridden = true;
      sdkConstraints['dart'] = VersionRange(
          min: parsedDartSdkConstraint.min,
          includeMin: parsedDartSdkConstraint.includeMin,
          max: sdk.version,
          includeMax: true);
    }

    _sdkConstraints = UnmodifiableMapView(sdkConstraints);
  }

  /// Whether or not we should override [sdkConstraint] to be <= the user's
  /// current SDK version.
  ///
  /// This is true if the following conditions are met:
  ///
  ///   - [_allowPreReleaseSdk] is `true`
  ///   - The user's current SDK is a pre-release version.
  ///   - The original [sdkConstraint] max version is exclusive (`includeMax`
  ///     is `false`).
  ///   - The original [sdkConstraint] is not a pre-release version.
  ///   - The original [sdkConstraint] matches the exact same major, minor, and
  ///     patch versions as the user's current SDK.
  bool _shouldEnableCurrentSdk(VersionRange sdkConstraint) {
    if (!_allowPreReleaseSdk) return false;
    if (!sdk.version.isPreRelease) return false;
    if (sdkConstraint.includeMax) return false;
    if (sdkConstraint.min != null &&
        sdkConstraint.min.isPreRelease &&
        equalsIgnoringPreRelease(sdkConstraint.min, sdk.version)) {
      return false;
    }
    if (sdkConstraint.max == null) return false;
    if (sdkConstraint.max.isPreRelease &&
        !sdkConstraint.max.isFirstPreRelease) {
      return false;
    }
    return equalsIgnoringPreRelease(sdkConstraint.max, sdk.version);
  }

  /// Parses the "environment" field in [parent] and returns a map from SDK
  /// identifiers to constraints on those SDKs.
  Map<String, VersionConstraint> _parseEnvironment(YamlMap parent) {
    var yaml = parent['environment'];
    if (yaml == null) {
      return {
        'dart': _includeDefaultSdkConstraint
            ? _defaultUpperBoundSdkConstraint
            : VersionConstraint.any
      };
    }

    if (yaml is! Map) {
      _error('"environment" field must be a map.',
          parent.nodes['environment'].span);
    }

    var constraints = {
      'dart': _parseVersionConstraint(yaml.nodes['sdk'],
          defaultUpperBoundConstraint: _includeDefaultSdkConstraint
              ? _defaultUpperBoundSdkConstraint
              : null)
    };
    yaml.nodes.forEach((name, constraint) {
      if (name.value is! String) {
        _error('SDK names must be strings.', name.span);
      } else if (name.value == 'dart') {
        _error('Use "sdk" to for Dart SDK constraints.', name.span);
      }
      if (name.value == 'sdk') return;

      constraints[name.value as String] = _parseVersionConstraint(constraint);
    });

    return constraints;
  }

  /// The URL of the server that the package should default to being published
  /// to, "none" if the package should not be published, or `null` if it should
  /// be published to the default server.
  ///
  /// If this does return a URL string, it will be a valid parseable URL.
  String get publishTo {
    if (_parsedPublishTo) return _publishTo;

    var publishTo = fields['publish_to'];
    if (publishTo != null) {
      var span = fields.nodes['publish_to'].span;

      if (publishTo is! String) {
        _error('"publish_to" field must be a string.', span);
      }

      // It must be "none" or a valid URL.
      if (publishTo != 'none') {
        _wrapFormatException('"publish_to" field', span, () {
          var url = Uri.parse(publishTo);
          if (url.scheme.isEmpty) {
            throw FormatException('must be an absolute URL.');
          }
        });
      }
    }

    _parsedPublishTo = true;
    _publishTo = publishTo;
    return _publishTo;
  }

  bool _parsedPublishTo = false;
  String _publishTo;

  /// The executables that should be placed on the user's PATH when this
  /// package is globally activated.
  ///
  /// It is a map of strings to string. Each key is the name of the command
  /// that will be placed on the user's PATH. The value is the name of the
  /// .dart script (without extension) in the package's `bin` directory that
  /// should be run for that command. Both key and value must be "simple"
  /// strings: alphanumerics, underscores and hypens only. If a value is
  /// omitted, it is inferred to use the same name as the key.
  Map<String, String> get executables {
    if (_executables != null) return _executables;

    _executables = {};
    var yaml = fields['executables'];
    if (yaml == null) return _executables;

    if (yaml is! Map) {
      _error('"executables" field must be a map.',
          fields.nodes['executables'].span);
    }

    yaml.nodes.forEach((key, value) {
      if (key.value is! String) {
        _error('"executables" keys must be strings.', key.span);
      }

      final keyPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
      if (!keyPattern.hasMatch(key.value)) {
        _error(
            '"executables" keys may only contain letters, '
            'numbers, hyphens and underscores.',
            key.span);
      }

      if (value.value == null) {
        value = key;
      } else if (value.value is! String) {
        _error('"executables" values must be strings or null.', value.span);
      }

      final valuePattern = RegExp(r'[/\\]');
      if (valuePattern.hasMatch(value.value)) {
        _error('"executables" values may not contain path separators.',
            value.span);
      }

      _executables[key.value] = value.value;
    });

    return _executables;
  }

  Map<String, String> _executables;

  /// Whether the package is private and cannot be published.
  ///
  /// This is specified in the pubspec by setting "publish_to" to "none".
  bool get isPrivate => publishTo == 'none';

  /// Whether or not the pubspec has no contents.
  bool get isEmpty =>
      name == null && version == Version.none && dependencies.isEmpty;

  /// Loads the pubspec for a package located in [packageDir].
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [PubspecException].
  factory Pubspec.load(String packageDir, SourceRegistry sources,
      {String expectedName, bool includeDefaultSdkConstraint}) {
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
        expectedName: expectedName,
        includeDefaultSdkConstraint: includeDefaultSdkConstraint,
        location: pubspecUri);
  }

  Pubspec(this._name,
      {Version version,
      Iterable<PackageRange> dependencies,
      Iterable<PackageRange> devDependencies,
      Iterable<PackageRange> dependencyOverrides,
      Map fields,
      SourceRegistry sources,
      Map<String, VersionConstraint> sdkConstraints})
      : _version = version,
        _dependencies = dependencies == null
            ? null
            : Map.fromIterable(dependencies, key: (range) => range.name),
        _devDependencies = devDependencies == null
            ? null
            : Map.fromIterable(devDependencies, key: (range) => range.name),
        _dependencyOverrides = dependencyOverrides == null
            ? null
            : Map.fromIterable(dependencyOverrides, key: (range) => range.name),
        _sdkConstraints = sdkConstraints ??
            UnmodifiableMapView({'dart': VersionConstraint.any}),
        _includeDefaultSdkConstraint = false,
        fields = fields == null ? YamlMap() : YamlMap.wrap(fields),
        _sources = sources;

  Pubspec.empty()
      : _sources = null,
        _name = null,
        _version = Version.none,
        _dependencies = {},
        _devDependencies = {},
        _sdkConstraints = {'dart': VersionConstraint.any},
        _includeDefaultSdkConstraint = false,
        fields = YamlMap();

  /// Returns a Pubspec object for an already-parsed map representing its
  /// contents.
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [PubspecError].
  ///
  /// [location] is the location from which this pubspec was loaded.
  Pubspec.fromMap(Map fields, this._sources,
      {String expectedName, bool includeDefaultSdkConstraint, Uri location})
      : fields = fields is YamlMap
            ? fields
            : YamlMap.wrap(fields, sourceUrl: location),
        _includeDefaultSdkConstraint = includeDefaultSdkConstraint ?? true {
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
      {String expectedName, bool includeDefaultSdkConstraint, Uri location}) {
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
        expectedName: expectedName,
        includeDefaultSdkConstraint: includeDefaultSdkConstraint,
        location: location);
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
    _collectError(_ensureEnvironment);
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

      var versionConstraint = VersionRange();
      var features = const <String, FeatureDependency>{};
      if (spec == null) {
        descriptionNode = nameNode;
        sourceName = _sources.defaultSource.name;
      } else if (spec is String) {
        descriptionNode = nameNode;
        sourceName = _sources.defaultSource.name;
        versionConstraint = _parseVersionConstraint(specNode);
      } else if (spec is Map) {
        // Don't write to the immutable YAML map.
        spec = Map.from(spec);
        var specMap = specNode as YamlMap;

        if (spec.containsKey('version')) {
          spec.remove('version');
          versionConstraint = _parseVersionConstraint(specMap.nodes['version']);
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

  /// Parses [node] to a [VersionConstraint].
  ///
  /// If or [defaultUpperBoundConstraint] is specified then it will be set as
  /// the max constraint if the original constraint doesn't have an upper
  /// bound and it is compatible with [defaultUpperBoundConstraint].
  VersionConstraint _parseVersionConstraint(YamlNode node,
      {VersionConstraint defaultUpperBoundConstraint}) {
    if (node?.value == null) {
      return defaultUpperBoundConstraint ?? VersionConstraint.any;
    }
    if (node.value is! String) {
      _error('A version constraint must be a string.', node.span);
    }

    return _wrapFormatException('version constraint', node.span, () {
      var constraint = VersionConstraint.parse(node.value);
      if (defaultUpperBoundConstraint != null &&
          constraint is VersionRange &&
          constraint.max == null &&
          defaultUpperBoundConstraint.allowsAny(constraint)) {
        constraint = VersionConstraint.intersection(
            [constraint, defaultUpperBoundConstraint]);
      }
      return constraint;
    });
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
    } else if (!_packageName.hasMatch(name)) {
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

/// An exception thrown when parsing a pubspec.
///
/// These exceptions are often thrown lazily while accessing pubspec properties.
class PubspecException extends SourceSpanFormatException
    implements ApplicationException {
  PubspecException(String message, SourceSpan span) : super(message, span);
}

/// Returns whether [uri] is a file URI.
///
/// This is slightly more complicated than just checking if the scheme is
/// 'file', since relative URIs also refer to the filesystem on the VM.
bool _isFileUri(Uri uri) => uri.scheme == 'file' || uri.scheme == '';
