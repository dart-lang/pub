// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'barback/transformer_config.dart';
import 'compiler.dart';
import 'exceptions.dart';
import 'feature.dart';
import 'io.dart';
import 'package_name.dart';
import 'source_registry.dart';
import 'utils.dart';

/// A regular expression matching allowed package names.
///
/// This allows dot-separated valid Dart identifiers. The dots are there for
/// compatibility with Google's internal Dart packages, but they may not be used
/// when publishing a package to pub.dartlang.org.
final _packageName = new RegExp(
    "^${identifierRegExp.pattern}(\\.${identifierRegExp.pattern})*\$");

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

  /// The package's name.
  String get name {
    if (_name != null) return _name;

    var name = fields['name'];
    if (name == null) {
      throw new PubspecException(
          'Missing the required "name" field.', fields.span);
    } else if (name is! String) {
      throw new PubspecException(
          '"name" field must be a string.', fields.nodes['name'].span);
    } else if (!_packageName.hasMatch(name)) {
      throw new PubspecException(
          '"name" field must be a valid Dart identifier.',
          fields.nodes['name'].span);
    } else if (reservedWords.contains(name)) {
      throw new PubspecException(
          '"name" field may not be a Dart reserved word.',
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
        'version number', span, () => new Version.parse(version));
    return _version;
  }

  Version _version;

  /// The additional packages this package depends on.
  List<PackageRange> get dependencies {
    if (_dependencies != null) return _dependencies;
    _dependencies =
        _parseDependencies('dependencies', fields.nodes['dependencies']);
    _checkDependencyOverlap(_dependencies, _devDependencies);
    return _dependencies;
  }

  List<PackageRange> _dependencies;

  /// The packages this package depends on when it is the root package.
  List<PackageRange> get devDependencies {
    if (_devDependencies != null) return _devDependencies;
    _devDependencies = _parseDependencies(
        'dev_dependencies', fields.nodes['dev_dependencies']);
    _checkDependencyOverlap(_dependencies, _devDependencies);
    return _devDependencies;
  }

  List<PackageRange> _devDependencies;

  /// The dependency constraints that this package overrides when it is the
  /// root package.
  ///
  /// Dependencies here will replace any dependency on a package with the same
  /// name anywhere in the dependency graph.
  List<PackageRange> get dependencyOverrides {
    if (_dependencyOverrides != null) return _dependencyOverrides;
    _dependencyOverrides = _parseDependencies(
        'dependency_overrides', fields.nodes['dependency_overrides']);
    return _dependencyOverrides;
  }

  List<PackageRange> _dependencyOverrides;

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
            return new Feature(nameNode.value, const []);
          }

          if (specNode is! Map) {
            _error('A feature specification must be a map.', specNode.span);
          }

          var onByDefault = specNode['default'] ?? true;
          if (onByDefault is! bool) {
            _error('Default must be true or false.',
                specNode.nodes['default'].span);
          }

          var dependencies = _parseDependencies(
              'dependencies', specNode.nodes['dependencies']);

          var sdkConstraints = _parseEnvironment(specNode);

          return new Feature(nameNode.value, dependencies,
              dartSdkConstraint: sdkConstraints.first,
              flutterSdkConstraint: sdkConstraints.last,
              onByDefault: onByDefault);
        });
    return _features;
  }

  Map<String, Feature> _features;

  /// The configurations of the transformers to use for this package.
  List<Set<TransformerConfig>> get transformers {
    if (_transformers != null) return _transformers;

    var transformers = fields['transformers'];
    if (transformers == null) {
      _transformers = [];
      return _transformers;
    }

    if (transformers is! List) {
      _error('"transformers" field must be a list.',
          fields.nodes['transformers'].span);
    }

    _transformers = (transformers as YamlList).nodes.map((phase) {
      var phaseNodes = phase is YamlList ? phase.nodes : [phase];
      return phaseNodes.map((transformerNode) {
        var transformer = transformerNode.value;
        if (transformer is! String && transformer is! Map) {
          _error(
              'A transformer must be a string or map.', transformerNode.span);
        }

        var libraryNode;
        var configurationNode;
        if (transformer is String) {
          libraryNode = transformerNode;
        } else {
          if (transformer.length != 1) {
            _error(
                'A transformer map must have a single key: the transformer '
                'identifier.',
                transformerNode.span);
          } else if (transformer.keys.single is! String) {
            _error('A transformer identifier must be a string.',
                transformer.nodes.keys.single.span);
          }

          libraryNode = transformer.nodes.keys.single;
          configurationNode = transformer.nodes.values.single;
          if (configurationNode is! YamlMap) {
            _error("A transformer's configuration must be a map.",
                configurationNode.span);
          }
        }

        var config = _wrapSpanFormatException('transformer config', () {
          return new TransformerConfig.parse(
              libraryNode.value, libraryNode.span, configurationNode);
        });

        var package = config.id.package;
        if (package != name &&
            !config.id.isBuiltInTransformer &&
            !_hasDependency(package)) {
          _error('"$package" is not a dependency.', libraryNode.span);
        }

        return config;
      }).toSet();
    }).toList();

    return _transformers;
  }

  List<Set<TransformerConfig>> _transformers;

  /// Returns whether this pubspec has any kind of dependency on [package].
  ///
  /// This explicitly avoids calling [_parseDependencies] because parsing dev
  /// dependencies can fail for a hosted package's pubspec (e.g. if that package
  /// has a relative path dev dependency).
  bool _hasDependency(String package) {
    return ['dependencies', 'dev_dependencies', 'dependency_overrides']
        .any((field) {
      var map = fields[field];
      if (map == null) return false;

      if (map is! Map) {
        _error('"$field" field must be a map.', fields.nodes[field].span);
      }

      return map.containsKey(package);
    });
  }

  /// The constraint on the Dart SDK, or [VersionConstraint.any] if none is
  /// specified.
  VersionConstraint get dartSdkConstraint {
    _ensureEnvironment();
    return _dartSdkConstraint;
  }

  VersionConstraint _dartSdkConstraint;

  /// The constraint on the Flutter SDK, or `null` if none is specified.
  VersionConstraint get flutterSdkConstraint {
    _ensureEnvironment();
    return _flutterSdkConstraint;
  }

  VersionConstraint _flutterSdkConstraint;

  /// Ensures that the top-level "environment" field has been parsed and
  /// [_dartSdkConstraint] and [_flutterSdkConstraint] are set accordingly.
  void _ensureEnvironment() {
    if (_dartSdkConstraint != null) return;

    var pair = _parseEnvironment(fields);
    _dartSdkConstraint = pair.first;
    _flutterSdkConstraint = pair.last;
  }

  /// Parses the "environment" field in [parent] and returns the Dart and
  /// Flutter SDK constraints, respectively.
  Pair<VersionConstraint, VersionConstraint> _parseEnvironment(YamlMap parent) {
    var yaml = parent['environment'];
    if (yaml == null) {
      return new Pair(VersionConstraint.any, null);
    }

    if (yaml is! Map) {
      _error('"environment" field must be a map.',
          parent.nodes['environment'].span);
    }

    return new Pair(
        _parseVersionConstraint(yaml.nodes['sdk']),
        yaml.containsKey('flutter')
            ? _parseVersionConstraint(yaml.nodes['flutter'])
            : null);
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
      if (publishTo != "none") {
        _wrapFormatException(
            '"publish_to" field', span, () => Uri.parse(publishTo));
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

      final keyPattern = new RegExp(r"^[a-zA-Z0-9_-]+$");
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

      final valuePattern = new RegExp(r"[/\\]");
      if (valuePattern.hasMatch(value.value)) {
        _error('"executables" values may not contain path separators.',
            value.span);
      }

      _executables[key.value] = value.value;
    });

    return _executables;
  }

  Map<String, String> _executables;

  /// The settings for which web compiler to use in which mode.
  ///
  /// It is a map of [String] to [Compiler]. Each key is the name of a mode, and
  /// the value is the web compiler to use in that mode.
  ///
  /// Valid compiler values are all of [Compiler.names].
  Map<String, Compiler> get webCompiler {
    if (_webCompiler != null) return _webCompiler;

    _webCompiler = <String, Compiler>{};
    var webYaml = fields.nodes['web'];
    if (webYaml?.value == null) return _webCompiler;

    if (webYaml is! Map) {
      _error('"web" field must be a map.', webYaml.span);
    }

    var compilerYaml = (webYaml as YamlMap)['compiler'];
    if (compilerYaml == null) return _webCompiler;

    if (compilerYaml is! Map) {
      _error('"compiler" field must be a map.',
          (webYaml as YamlMap).nodes['compiler'].span);
    }

    compilerYaml.nodes.forEach((key, value) {
      if (key.value is! String) {
        _error('"compiler" keys must be strings.', key.span);
      }

      if (!Compiler.names.contains(value.value)) {
        _error(
            '"compiler" values must be one of ${Compiler.names}.', value.span);
      }

      _webCompiler[key.value] = Compiler.byName(value.value);
    });

    return _webCompiler;
  }

  Map<String, Compiler> _webCompiler;

  /// Whether the package is private and cannot be published.
  ///
  /// This is specified in the pubspec by setting "publish_to" to "none".
  bool get isPrivate => publishTo == "none";

  /// Whether or not the pubspec has no contents.
  bool get isEmpty =>
      name == null && version == Version.none && dependencies.isEmpty;

  /// Loads the pubspec for a package located in [packageDir].
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [PubspecError].
  factory Pubspec.load(String packageDir, SourceRegistry sources,
      {String expectedName}) {
    var pubspecPath = path.join(packageDir, 'pubspec.yaml');
    var pubspecUri = path.toUri(pubspecPath);
    if (!fileExists(pubspecPath)) {
      throw new FileException(
          // Make the package dir absolute because for the entrypoint it'll just
          // be ".", which may be confusing.
          'Could not find a file named "pubspec.yaml" in '
          '"${canonicalize(packageDir)}".',
          pubspecPath);
    }

    return new Pubspec.parse(readTextFile(pubspecPath), sources,
        expectedName: expectedName, location: pubspecUri);
  }

  Pubspec(this._name,
      {Version version,
      Iterable<PackageRange> dependencies,
      Iterable<PackageRange> devDependencies,
      Iterable<PackageRange> dependencyOverrides,
      VersionConstraint dartSdkConstraint,
      VersionConstraint flutterSdkConstraint,
      Iterable<Iterable<TransformerConfig>> transformers,
      Map fields,
      SourceRegistry sources})
      : _version = version,
        _dependencies = dependencies == null ? null : dependencies.toList(),
        _devDependencies =
            devDependencies == null ? null : devDependencies.toList(),
        _dependencyOverrides =
            dependencyOverrides == null ? null : dependencyOverrides.toList(),
        _dartSdkConstraint = dartSdkConstraint ?? VersionConstraint.any,
        _flutterSdkConstraint = flutterSdkConstraint,
        _transformers = transformers == null
            ? []
            : transformers.map((phase) => phase.toSet()).toList(),
        fields = fields == null ? new YamlMap() : new YamlMap.wrap(fields),
        _sources = sources;

  Pubspec.empty()
      : _sources = null,
        _name = null,
        _version = Version.none,
        _dependencies = <PackageRange>[],
        _devDependencies = <PackageRange>[],
        _dartSdkConstraint = VersionConstraint.any,
        _flutterSdkConstraint = null,
        _transformers = <Set<TransformerConfig>>[],
        fields = new YamlMap();

  /// Returns a Pubspec object for an already-parsed map representing its
  /// contents.
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [PubspecError].
  ///
  /// [location] is the location from which this pubspec was loaded.
  Pubspec.fromMap(Map fields, this._sources,
      {String expectedName, Uri location})
      : fields = fields is YamlMap
            ? fields
            : new YamlMap.wrap(fields, sourceUrl: location) {
    // If [expectedName] is passed, ensure that the actual 'name' field exists
    // and matches the expectation.
    if (expectedName == null) return;
    if (name == expectedName) return;

    throw new PubspecException(
        '"name" field doesn\'t match expected name '
        '"$expectedName".',
        this.fields.nodes["name"].span);
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
      throw new PubspecException(error.message, error.span);
    }

    Map pubspecMap;
    if (pubspecNode is YamlScalar && pubspecNode.value == null) {
      pubspecMap = new YamlMap(sourceUrl: location);
    } else if (pubspecNode is YamlMap) {
      pubspecMap = pubspecNode;
    } else {
      throw new PubspecException(
          'The pubspec must be a YAML mapping.', pubspecNode.span);
    }

    return new Pubspec.fromMap(pubspecMap, sources,
        expectedName: expectedName, location: location);
  }

  /// Returns a list of most errors in this pubspec.
  ///
  /// This will return at most one error for each field.
  List<PubspecException> get allErrors {
    var errors = <PubspecException>[];
    _getError(fn()) {
      try {
        fn();
      } on PubspecException catch (e) {
        errors.add(e);
      }
    }

    _getError(() => this.name);
    _getError(() => this.version);
    _getError(() => this.dependencies);
    _getError(() => this.devDependencies);
    _getError(() => this.transformers);
    _getError(() => this.publishTo);
    _getError(() => this.features);
    _getError(() => this._ensureEnvironment());
    return errors;
  }

  /// Parses the dependency field named [field], and returns the corresponding
  /// list of dependencies.
  List<PackageRange> _parseDependencies(String field, YamlNode node) {
    var dependencies = <PackageRange>[];

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

      var descriptionNode;
      var sourceName;

      var versionConstraint = new VersionRange();
      Map<String, bool> features = const {};
      if (spec == null) {
        descriptionNode = nameNode;
        sourceName = _sources.defaultSource.name;
      } else if (spec is String) {
        descriptionNode = nameNode;
        sourceName = _sources.defaultSource.name;
        versionConstraint = _parseVersionConstraint(specNode);
      } else if (spec is Map) {
        // Don't write to the immutable YAML map.
        spec = new Map.from(spec);
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
          // Default to a hosted dependency if no source is specifid.
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
        var pubspecPath;
        if (_location != null && _isFileUri(_location)) {
          pubspecPath = path.fromUri(_location);
        }

        return _sources[sourceName].parseRef(name, descriptionNode?.value,
            containingPath: pubspecPath);
      });

      dependencies
          .add(ref.withConstraint(versionConstraint).withFeatures(features));
    });

    return dependencies;
  }

  /// Parses [node] to a [VersionConstraint].
  VersionConstraint _parseVersionConstraint(YamlNode node) {
    if (node?.value == null) return VersionConstraint.any;
    if (node.value is! String) {
      _error('A version constraint must be a string.', node.span);
    }

    return _wrapFormatException('version constraint', node.span,
        () => new VersionConstraint.parse(node.value));
  }

  /// Parses [node] to a map from feature names to whether those features are
  /// enabled.
  Map<String, bool> _parseDependencyFeatures(YamlNode node) {
    if (node?.value == null) return const {};
    if (node is! YamlMap) _error('Features must be a map.', node.span);

    return mapMap((node as YamlMap).nodes,
        key: (nameNode, _) => _validateFeatureName(nameNode),
        value: (_, valueNode) {
          var value = valueNode.value;
          if (value is bool) return value;
          _error('Features must be true or false.', valueNode.span);
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

  /// Makes sure the same package doesn't appear as both a regular and dev
  /// dependency.
  void _checkDependencyOverlap(
      List<PackageRange> dependencies, List<PackageRange> devDependencies) {
    if (dependencies == null) return;
    if (devDependencies == null) return;

    var dependencyNames = dependencies.map((dep) => dep.name).toSet();
    var collisions = dependencyNames
        .intersection(devDependencies.map((dep) => dep.name).toSet());
    if (collisions.isEmpty) return;

    var span = fields["dependencies"]
        .nodes
        .keys
        .firstWhere((key) => collisions.contains(key.value))
        .span;

    // TODO(nweiz): associate source range info with PackageRanges and use it
    // here.
    _error(
        '${pluralize('Package', collisions.length)} '
        '${toSentence(collisions.map((package) => '"$package"'))} cannot '
        'appear in both "dependencies" and "dev_dependencies".',
        span);
  }

  /// Runs [fn] and wraps any [FormatException] it throws in a
  /// [PubspecException].
  ///
  /// [description] should be a noun phrase that describes whatever's being
  /// parsed or processed by [fn]. [span] should be the location of whatever's
  /// being processed within the pubspec.
  _wrapFormatException(String description, SourceSpan span, fn()) {
    try {
      return fn();
    } on FormatException catch (e) {
      _error('Invalid $description: ${e.message}', span);
    }
  }

  _wrapSpanFormatException(String description, fn()) {
    try {
      return fn();
    } on SourceSpanFormatException catch (e) {
      _error('Invalid $description: ${e.message}', e.span);
    }
  }

  /// Throws a [PubspecException] with the given message.
  void _error(String message, SourceSpan span) {
    throw new PubspecException(message, span);
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
