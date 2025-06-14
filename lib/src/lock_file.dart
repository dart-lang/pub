// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart' hide mapMap;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'io.dart';
import 'language_version.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'system_cache.dart';
import 'utils.dart';

/// A parsed and validated `pubspec.lock` file.
class LockFile {
  /// The packages this lockfile pins.
  final Map<String, PackageId> packages;

  /// The intersections of all SDK constraints for all locked packages, indexed
  /// by SDK identifier.
  final Map<String, SdkConstraint> sdkConstraints;

  /// Dependency names that appeared in the root package's `dependencies`
  /// section.
  final Set<String> mainDependencies;

  /// Dependency names that appeared in the root package's `dev_dependencies`
  /// section.
  final Set<String> devDependencies;

  /// Dependency names that appeared in the root package's
  /// `dependency_overrides` section.
  final Set<String> overriddenDependencies;

  /// Creates a new lockfile containing [ids].
  ///
  /// If passed, [mainDependencies], [devDependencies], and
  /// [overriddenDependencies] indicate which dependencies should be marked as
  /// being listed in the main package's `dependencies`, `dev_dependencies`, and
  /// `dependency_overrides` sections, respectively. These are consumed by the
  /// analysis server to provide better auto-completion.
  LockFile(
    Iterable<PackageId> ids, {
    Map<String, SdkConstraint>? sdkConstraints,
    Set<String>? mainDependencies,
    Set<String>? devDependencies,
    Set<String>? overriddenDependencies,
  }) : this._(
         {
           for (final id in ids)
             if (!id.isRoot) id.name: id,
         },
         sdkConstraints ?? {'dart': SdkConstraint(VersionConstraint.any)},
         mainDependencies ?? const UnmodifiableSetView.empty(),
         devDependencies ?? const UnmodifiableSetView.empty(),
         overriddenDependencies ?? const UnmodifiableSetView.empty(),
       );

  LockFile._(
    Map<String, PackageId> packages,
    this.sdkConstraints,
    this.mainDependencies,
    this.devDependencies,
    this.overriddenDependencies,
  ) : packages = UnmodifiableMapView(packages);

  LockFile.empty()
    : packages = const {},
      sdkConstraints = {'dart': SdkConstraint(VersionConstraint.any)},
      mainDependencies = const UnmodifiableSetView.empty(),
      devDependencies = const UnmodifiableSetView.empty(),
      overriddenDependencies = const UnmodifiableSetView.empty();

  /// Loads a lockfile from [filePath].
  factory LockFile.load(String filePath, SourceRegistry sources) {
    return LockFile._parse(filePath, readTextFile(filePath), sources);
  }

  /// Parses a lockfile whose text is [contents].
  ///
  /// If [filePath] is given, path-dependencies will be interpreted relative to
  /// that.
  factory LockFile.parse(
    String contents,
    SourceRegistry sources, {
    String? filePath,
  }) {
    return LockFile._parse(filePath, contents, sources);
  }

  /// Parses the lockfile whose text is [contents].
  ///
  /// [filePath] is the system-native path to the lockfile on disc. It may be
  /// `null`.
  static LockFile _parse(
    String? filePath,
    String contents,
    SourceRegistry sources,
  ) {
    if (contents.trim() == '') return LockFile.empty();

    Uri? sourceUrl;
    if (filePath != null) sourceUrl = p.toUri(filePath);
    final parsed = _parseNode<YamlMap>(
      loadYamlNode(contents, sourceUrl: sourceUrl),
      'YAML mapping',
    );

    final sdkConstraints = <String, SdkConstraint>{};
    final sdkNode = _getEntry<YamlScalar?>(
      parsed,
      'sdk',
      'string',
      required: false,
    );
    if (sdkNode != null) {
      // Lockfiles produced by pub versions from 1.14.0 through 1.18.0 included
      // a top-level "sdk" field which encoded the unified constraint on the
      // Dart SDK. They had no way of specifying constraints on other SDKs.
      sdkConstraints['dart'] = SdkConstraint.interpretDartSdkConstraint(
        _parseVersionConstraint(sdkNode),
        defaultUpperBoundConstraint: null,
      );
    }

    final sdksField = _getEntry<YamlMap?>(
      parsed,
      'sdks',
      'map',
      required: false,
    );

    if (sdksField != null) {
      _parseEachEntry<String, YamlScalar>(
        sdksField,
        (name, constraint) {
          final originalConstraint = _parseVersionConstraint(constraint);
          // Reinterpret the sdk constraints here, in case they were written by
          // an old sdk that did not do reinterpretations.
          // TODO(sigurdm): push the switching into `SdkConstraint`.
          sdkConstraints[name] = switch (name) {
            'dart' => SdkConstraint.interpretDartSdkConstraint(
              originalConstraint,
              defaultUpperBoundConstraint: null,
            ),
            'flutter' => SdkConstraint.interpretFlutterSdkConstraint(
              originalConstraint,
              isRoot: false,
              languageVersion: LanguageVersion.defaultLanguageVersion,
            ),
            _ => SdkConstraint(originalConstraint),
          };
        },
        'string',
        'string',
      );
    }

    final packages = <String, PackageId>{};

    final mainDependencies = <String>{};
    final devDependencies = <String>{};
    final overriddenDependencies = <String>{};

    final packageEntries = _getEntry<YamlMap?>(
      parsed,
      'packages',
      'map',
      required: false,
    );

    if (packageEntries != null) {
      _parseEachEntry<String, YamlMap>(
        packageEntries,
        (name, spec) {
          // Parse the version.
          final versionEntry = _getEntry<YamlScalar>(
            spec,
            'version',
            'version string',
          );
          final version = _parseVersion(versionEntry);

          // Parse the source.
          final sourceName = _getStringEntry(spec, 'source');

          final descriptionNode = _getEntry<YamlNode>(
            spec,
            'description',
            'description',
          );

          final dynamic description =
              descriptionNode is YamlScalar
                  ? descriptionNode.value
                  : descriptionNode;

          // Let the source parse the description.
          final source = sources(sourceName);
          PackageId id;
          try {
            id = source.parseId(
              name,
              version,
              description,
              containingDir: filePath == null ? null : p.dirname(filePath),
            );
          } on FormatException catch (ex) {
            _failAt(ex.message, spec.nodes['description']!);
          }

          // Validate the name.
          if (name != id.name) {
            _failAt("Package name $name doesn't match ${id.name}.", spec);
          }

          packages[name] = id;
          if (spec.containsKey('dependency')) {
            final dependencyKind = _getStringEntry(spec, 'dependency');
            switch (dependencyKind) {
              case _directMain:
                mainDependencies.add(name);
                break;
              case _directDev:
                devDependencies.add(name);
                break;
              case _directOverridden:
                overriddenDependencies.add(name);
            }
          }
        },
        'string',
        'map',
      );
    }
    return LockFile._(
      packages,
      sdkConstraints,
      mainDependencies,
      devDependencies,
      overriddenDependencies,
    );
  }

  /// Runs [fn] and wraps any [FormatException] it throws in a
  /// [SourceSpanFormatException].
  ///
  /// [description] should be a noun phrase that describes whatever's being
  /// parsed or processed by [fn]. [span] should be the location of whatever's
  /// being processed within the pubspec.
  static T _wrapFormatException<T>(
    String description,
    SourceSpan span,
    T Function() fn,
  ) {
    try {
      return fn();
    } on FormatException catch (e) {
      throw SourceSpanFormatException('$description: ${e.message}', span);
    }
  }

  static VersionConstraint _parseVersionConstraint(YamlNode node) {
    return _parseNode(
      node,
      'version constraint',
      parse: VersionConstraint.parse,
    );
  }

  static Version _parseVersion(YamlNode node) {
    return _parseNode(node, 'version', parse: Version.parse);
  }

  static String _getStringEntry(YamlMap map, String key) {
    return _parseNode<String>(
      _getEntry<YamlScalar>(map, key, 'string'),
      'string',
    );
  }

  static T _parseNode<T>(
    YamlNode node,
    String typeDescription, {
    T Function(String)? parse,
  }) {
    if (node is T) {
      return node as T;
    } else if (node is YamlScalar) {
      final value = node.value;
      if (parse != null) {
        if (value is! String) {
          _failAt('Expected a $typeDescription', node);
        }
        return _wrapFormatException(
          'Expected a $typeDescription',
          node.span,
          () => parse(value),
        );
      } else if (value is T) {
        return value;
      }
      _failAt('Expected a $typeDescription', node);
    }
    _failAt('Expected a $typeDescription', node);
  }

  static void _parseEachEntry<K, V>(
    YamlMap map,
    void Function(K key, V value) f,
    String keyTypeDescription,
    String valueTypeDescription,
  ) {
    map.nodes.forEach((key, value) {
      f(
        _parseNode(key as YamlNode, keyTypeDescription),
        _parseNode(value, valueTypeDescription),
      );
    });
  }

  static T _getEntry<T>(
    YamlMap map,
    String key,
    String type, {
    bool required = true,
  }) {
    final entry = map.nodes[key];
    // `null` here always means not present. A value explicitly mapped to `null`
    // would be a `YamlScalar(null)`.
    if (entry == null) {
      if (required) {
        _failAt('Expected a `$key` entry.', map);
      } else {
        return null as T;
      }
    }
    return _parseNode(entry, type);
  }

  static Never _failAt(String message, YamlNode node) {
    throw SourceSpanFormatException(message, node.span);
  }

  /// Returns a copy of this LockFile with a package named [name] removed.
  ///
  /// Returns an identical [LockFile] if there's no package named [name].
  LockFile removePackage(String name) {
    if (!this.packages.containsKey(name)) return this;

    final packages = Map<String, PackageId>.from(this.packages);
    packages.remove(name);
    return LockFile._(
      packages,
      sdkConstraints,
      mainDependencies,
      devDependencies,
      overriddenDependencies,
    );
  }

  /// Returns the serialized YAML text of the lock file.
  ///
  /// [packageDir] is the containing directory of the root package, used to
  /// serialize relative path package descriptions. If it is null, they will be
  /// serialized as absolute.
  String serialize(String? packageDir, SystemCache cache) {
    // Convert the dependencies to a simple object.
    final packageMap = <String, Object?>{};
    for (final id in packages.values) {
      packageMap[id.name] = {
        'version': id.version.toString(),
        'source': id.source.name,
        'description': id.description.serializeForLockfile(
          containingDir: packageDir,
        ),
        'dependency': _dependencyType(id.name),
      };
    }

    final data = {
      'sdks': mapMap<String, SdkConstraint, String, String>(
        sdkConstraints,
        value: (_, constraint) => constraint.effectiveConstraint.toString(),
      ),
      'packages': packageMap,
    };
    return '''
# Generated by pub
# See https://dart.dev/tools/pub/glossary#lockfile
${yamlToString(data)}
''';
  }

  /// Saves the list of concrete package versions to [lockFilePath].
  ///
  /// Will use Windows line endings (`\r\n`) if the file already exists, and
  /// uses that.
  ///
  /// Relative paths will be resolved relative to [lockFilePath]
  void writeToFile(String lockFilePath, SystemCache cache) {
    final windowsLineEndings =
        fileExists(lockFilePath) &&
        detectWindowsLineEndings(readTextFile(lockFilePath));

    final serialized = serialize(p.dirname(lockFilePath), cache);
    writeTextFileIfDifferent(
      lockFilePath,
      windowsLineEndings ? serialized.replaceAll('\n', '\r\n') : serialized,
    );
  }

  static const _directMain = 'direct main';
  static const _directDev = 'direct dev';
  static const _directOverridden = 'direct overridden';
  static const _transitive = 'transitive';

  /// Returns the dependency classification for [package].
  String _dependencyType(String package) {
    if (mainDependencies.contains(package)) return _directMain;
    if (devDependencies.contains(package)) return _directDev;

    // If a package appears in `dependency_overrides` and another dependency
    // section, the main section it appears in takes precedence.
    if (overriddenDependencies.contains(package)) {
      return _directOverridden;
    }
    return _transitive;
  }

  /// Returns true if the packages in `this` and [other] are
  /// all the same, meaning:
  ///  * same set of package-names
  ///  * for each package
  ///    * same version number
  ///    * same resolved description (same content-hash, git hash, path)
  bool samePackageIds(LockFile other) {
    if (other.packages.length != packages.length) {
      return false;
    }
    for (final package in packages.values) {
      final oldPackage = other.packages[package.name];
      if (oldPackage == null) return false; // Package added to resolution.
      if (oldPackage.version != package.version) return false;
      if (oldPackage.description != package.description) return false;
    }
    return true;
  }
}

/// Returns `true` if the [text] looks like it uses windows line endings.
///
/// The heuristic used is to count all `\n` in the text and if strictly more
/// than half of them are preceded by `\r` we report `true`.
@visibleForTesting
bool detectWindowsLineEndings(String text) {
  var index = -1;
  var unixNewlines = 0;
  var windowsNewlines = 0;
  while ((index = text.indexOf('\n', index + 1)) != -1) {
    if (index != 0 && text[index - 1] == '\r') {
      windowsNewlines++;
    } else {
      unixNewlines++;
    }
  }
  return windowsNewlines > unixNewlines;
}
