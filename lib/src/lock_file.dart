// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';

import 'package:collection/collection.dart';
// ignore: deprecated_member_use
import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'io.dart';
import 'package_config.dart';
import 'package_name.dart';
import 'sdk.dart' show sdk;
import 'source_registry.dart';
import 'system_cache.dart';
import 'utils.dart';

/// A parsed and validated `pubspec.lock` file.
class LockFile {
  /// The packages this lockfile pins.
  final Map<String, PackageId> packages;

  /// The intersections of all SDK constraints for all locked packages, indexed
  /// by SDK identifier.
  Map<String, VersionConstraint> sdkConstraints;

  /// Dependency names that appeared in the root package's `dependencies`
  /// section.
  final Set<String> _mainDependencies;

  /// Dependency names that appeared in the root package's `dev_dependencies`
  /// section.
  final Set<String> _devDependencies;

  /// Dependency names that appeared in the root package's
  /// `dependency_overrides` section.
  final Set<String> _overriddenDependencies;

  /// Creates a new lockfile containing [ids].
  ///
  /// If passed, [mainDependencies], [devDependencies], and
  /// [overriddenDependencies] indicate which dependencies should be marked as
  /// being listed in the main package's `dependencies`, `dev_dependencies`, and
  /// `dependency_overrides` sections, respectively. These are consumed by the
  /// analysis server to provide better auto-completion.
  LockFile(Iterable<PackageId> ids,
      {Map<String, VersionConstraint> sdkConstraints,
      Set<String> mainDependencies,
      Set<String> devDependencies,
      Set<String> overriddenDependencies})
      : this._(
            Map.fromIterable(ids.where((id) => !id.isRoot),
                key: (id) => id.name),
            sdkConstraints ?? {'dart': VersionConstraint.any},
            mainDependencies ?? const UnmodifiableSetView.empty(),
            devDependencies ?? const UnmodifiableSetView.empty(),
            overriddenDependencies ?? const UnmodifiableSetView.empty());

  LockFile._(
      Map<String, PackageId> packages,
      this.sdkConstraints,
      this._mainDependencies,
      this._devDependencies,
      this._overriddenDependencies)
      : packages = UnmodifiableMapView(packages);

  LockFile.empty()
      : packages = const {},
        sdkConstraints = {'dart': VersionConstraint.any},
        _mainDependencies = const UnmodifiableSetView.empty(),
        _devDependencies = const UnmodifiableSetView.empty(),
        _overriddenDependencies = const UnmodifiableSetView.empty();

  /// Loads a lockfile from [filePath].
  factory LockFile.load(String filePath, SourceRegistry sources) {
    return LockFile._parse(filePath, readTextFile(filePath), sources);
  }

  /// Parses a lockfile whose text is [contents].
  factory LockFile.parse(String contents, SourceRegistry sources) {
    return LockFile._parse(null, contents, sources);
  }

  /// Parses the lockfile whose text is [contents].
  ///
  /// [filePath] is the system-native path to the lockfile on disc. It may be
  /// `null`.
  static LockFile _parse(
      String filePath, String contents, SourceRegistry sources) {
    if (contents.trim() == '') return LockFile.empty();

    Uri sourceUrl;
    if (filePath != null) sourceUrl = p.toUri(filePath);
    var parsed = loadYamlNode(contents, sourceUrl: sourceUrl);

    _validate(parsed is Map, 'The lockfile must be a YAML mapping.', parsed);
    var parsedMap = parsed as YamlMap;

    var sdkConstraints = <String, VersionConstraint>{};
    var sdkNode = parsedMap.nodes['sdk'];
    if (sdkNode != null) {
      // Lockfiles produced by pub versions from 1.14.0 through 1.18.0 included
      // a top-level "sdk" field which encoded the unified constraint on the
      // Dart SDK. They had no way of specifying constraints on other SDKs.
      sdkConstraints['dart'] = _parseVersionConstraint(sdkNode);
    } else if (parsedMap.containsKey('sdks')) {
      var sdksField = parsedMap['sdks'];
      _validate(sdksField is Map, 'The "sdks" field must be a mapping.',
          parsedMap.nodes['sdks']);

      sdksField.nodes.forEach((name, constraint) {
        _validate(name.value is String, 'SDK names must be strings.', name);
        sdkConstraints[name.value as String] =
            _parseVersionConstraint(constraint);
      });
    }

    var packages = <String, PackageId>{};
    var packageEntries = parsedMap['packages'];
    if (packageEntries != null) {
      _validate(packageEntries is Map, 'The "packages" field must be a map.',
          parsedMap.nodes['packages']);

      packageEntries.forEach((name, spec) {
        // Parse the version.
        _validate(spec.containsKey('version'),
            'Package $name is missing a version.', spec);
        var version = Version.parse(spec['version']);

        // Parse the source.
        _validate(spec.containsKey('source'),
            'Package $name is missing a source.', spec);
        var sourceName = spec['source'];

        _validate(spec.containsKey('description'),
            'Package $name is missing a description.', spec);
        var description = spec['description'];

        // Let the source parse the description.
        var source = sources[sourceName];
        PackageId id;
        try {
          id = source.parseId(name, version, description,
              containingPath: filePath);
        } on FormatException catch (ex) {
          throw SourceSpanFormatException(
              ex.message, spec.nodes['description'].span);
        }

        // Validate the name.
        _validate(name == id.name,
            "Package name $name doesn't match ${id.name}.", spec);

        packages[name] = id;
      });
    }

    return LockFile._(
        packages,
        sdkConstraints,
        const UnmodifiableSetView.empty(),
        const UnmodifiableSetView.empty(),
        const UnmodifiableSetView.empty());
  }

  /// Asserts that [node] is a version constraint, and parses it.
  static VersionConstraint _parseVersionConstraint(YamlNode node) {
    if (node == null) return null;

    _validate(node.value is String,
        'Invalid version constraint: must be a string.', node);

    return _wrapFormatException('version constraint', node.span,
        () => VersionConstraint.parse(node.value));
  }

  /// Runs [fn] and wraps any [FormatException] it throws in a
  /// [SourceSpanFormatException].
  ///
  /// [description] should be a noun phrase that describes whatever's being
  /// parsed or processed by [fn]. [span] should be the location of whatever's
  /// being processed within the pubspec.
  static T _wrapFormatException<T>(
      String description, SourceSpan span, T Function() fn) {
    try {
      return fn();
    } on FormatException catch (e) {
      throw SourceSpanFormatException(
          'Invalid $description: ${e.message}', span);
    }
  }

  /// If [condition] is `false` throws a format error with [message] for [node].
  static void _validate(bool condition, String message, YamlNode node) {
    if (condition) return;
    throw SourceSpanFormatException(message, node.span);
  }

  /// Returns a copy of this LockFile with a package named [name] removed.
  ///
  /// Returns an identical [LockFile] if there's no package named [name].
  LockFile removePackage(String name) {
    if (!this.packages.containsKey(name)) return this;

    var packages = Map<String, PackageId>.from(this.packages);
    packages.remove(name);
    return LockFile._(packages, sdkConstraints, _mainDependencies,
        _devDependencies, _overriddenDependencies);
  }

  /// Returns the contents of the `.packages` file generated from this lockfile.
  ///
  /// If [entrypoint] is passed, a relative entry is added for its "lib/"
  /// directory.
  String packagesFile(SystemCache cache, [String entrypoint]) {
    var header = 'Generated by pub on ${DateTime.now()}.';

    var map =
        Map<String, Uri>.fromIterable(ordered(packages.keys), value: (name) {
      var id = packages[name];
      var source = cache.source(id.source);
      return p.toUri(p.join(source.getDirectory(id), 'lib'));
    });

    if (entrypoint != null) map[entrypoint] = Uri.parse('lib/');

    var text = StringBuffer();
    packages_file.write(text, map, comment: header);
    return text.toString();
  }

  /// Returns the contents of the `.dart_tools/package_config` file generated
  /// from this lockfile.
  ///
  /// This file is planned to eventually replace the `.packages` file.
  ///
  /// If [entrypoint] is passed, an accompanying [entrypointSdkConstraint]
  /// should be given, these identify the current package in which this file is
  /// written. Passing `null` as [entrypointSdkConstraint] is correct if the
  /// current package has no SDK constraint.
  Future<String> packageConfigFile(
    SystemCache cache, {
    String entrypoint,
    VersionConstraint entrypointSdkConstraint,
  }) async {
    final entries = <PackageConfigEntry>[];
    for (final name in ordered(packages.keys)) {
      final id = packages[name];
      final source = cache.source(id.source);
      final rootPath = source.getDirectory(id);
      Uri rootUri;
      if (p.isRelative(rootPath)) {
        // Relative paths are relative to the root project, we want them
        // relative to the `.dart_tool/package_config.json` file.
        rootUri = p.toUri(p.join('..', rootPath));
      } else {
        rootUri = p.toUri(rootPath);
      }
      final pubspec = await source.describe(id);
      final sdkConstraint = pubspec.sdkConstraints[sdk.identifier];
      entries.add(PackageConfigEntry(
        name: name,
        rootUri: rootUri,
        packageUri: p.toUri('lib/'),
        languageVersion: extractLanguageVersion(sdkConstraint),
      ));
    }

    if (entrypoint != null) {
      entries.add(PackageConfigEntry(
        name: entrypoint,
        rootUri: p.toUri('../'),
        packageUri: p.toUri('lib/'),
        languageVersion: extractLanguageVersion(entrypointSdkConstraint),
      ));
    }

    final packageConfig = PackageConfig(
      configVersion: 2,
      packages: entries,
      generated: DateTime.now(),
      generator: 'pub',
      generatorVersion: sdk.version,
    );

    return JsonEncoder.withIndent('  ').convert(packageConfig.toJson()) + '\n';
  }

  /// Returns the serialized YAML text of the lock file.
  ///
  /// [packageDir] is the containing directory of the root package, used to
  /// properly serialize package descriptions.
  String serialize(String packageDir) {
    // Convert the dependencies to a simple object.
    var packageMap = {};
    packages.forEach((name, package) {
      var description =
          package.source.serializeDescription(packageDir, package.description);

      packageMap[name] = {
        'version': package.version.toString(),
        'source': package.source.name,
        'description': description,
        'dependency': _dependencyType(package.name)
      };
    });

    var data = {
      'sdks': mapMap(sdkConstraints,
          value: (_, constraint) => constraint.toString()),
      'packages': packageMap
    };
    return '''
# Generated by pub
# See https://dart.dev/tools/pub/glossary#lockfile
${yamlToString(data)}
''';
  }

  /// Returns the dependency classification for [package].
  String _dependencyType(String package) {
    if (_mainDependencies.contains(package)) return 'direct main';
    if (_devDependencies.contains(package)) return 'direct dev';

    // If a package appears in `dependency_overrides` and another dependency
    // section, the main section it appears in takes precedence.
    if (_overriddenDependencies.contains(package)) {
      return 'direct overridden';
    }
    return 'transitive';
  }
}
