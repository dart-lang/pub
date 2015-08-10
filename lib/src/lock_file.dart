// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub.lock_file;

import 'dart:collection';

import 'package:path/path.dart' as p;
import 'package:package_config/packages_file.dart' as packages_file;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'io.dart';
import 'package.dart';
import 'source_registry.dart';
import 'utils.dart';

/// A parsed and validated `pubspec.lock` file.
class LockFile {
  /// The source registry with which the lock file's IDs are interpreted.
  final SourceRegistry _sources;

  /// The packages this lockfile pins.
  final Map<String, PackageId> packages;

  /// Creates a new lockfile containing [ids].
  ///
  /// Throws an [ArgumentError] if any package has an unresolved ID according to
  /// [Source.isResolved].
  factory LockFile(Iterable<PackageId> ids, SourceRegistry sources) {
    var packages = {};
    for (var id in ids) {
      if (id.isRoot) continue;

      if (!sources[id.source].isResolved(id)) {
        throw new ArgumentError('ID "$id" is not resolved.');
      }

      packages[id.name] = id;
    }

    return new LockFile._(packages, sources);
  }

  LockFile._(Map<String, PackageId> packages, this._sources)
      : packages = new UnmodifiableMapView(packages);

  LockFile.empty(this._sources)
      : packages = const {};

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
  static LockFile _parse(String filePath, String contents,
      SourceRegistry sources) {
    var packages = {};

    if (contents.trim() == '') return new LockFile.empty(sources);

    var sourceUrl;
    if (filePath != null) sourceUrl = p.toUri(filePath);
    var parsed = loadYamlNode(contents, sourceUrl: sourceUrl);

    _validate(parsed is Map, 'The lockfile must be a YAML mapping.', parsed);

    var packageEntries = parsed['packages'];
    if (packageEntries != null) {
      _validate(packageEntries is Map, 'The "packages" field must be a map.',
          parsed.nodes['packages']);

      packageEntries.forEach((name, spec) {
        // Parse the version.
        _validate(spec.containsKey('version'),
            'Package $name is missing a version.', spec);
        var version = new Version.parse(spec['version']);

        // Parse the source.
        _validate(spec.containsKey('source'),
            'Package $name is missing a source.', spec);
        var sourceName = spec['source'];

        _validate(spec.containsKey('description'),
            'Package $name is missing a description.', spec);
        var description = spec['description'];

        // Let the source parse the description.
        var source = sources[sourceName];
        try {
          description = source.parseDescription(filePath, description,
              fromLockFile: true);
        } on FormatException catch (ex) {
          throw new SourceSpanFormatException(ex.message,
              spec.nodes['source'].span);
        }

        var id = new PackageId(name, sourceName, version, description);

        // Validate the name.
        _validate(name == id.name,
            "Package name $name doesn't match ${id.name}.", spec);

        packages[name] = id;
      });
    }

    return new LockFile._(packages, sources);
  }

  /// If [condition] is `false` throws a format error with [message] for [node].
  static void _validate(bool condition, String message, YamlNode node) {
    if (condition) return;
    throw new SourceSpanFormatException(message, node.span);
  }

  /// Returns a copy of this LockFile with [id] added.
  ///
  /// Throws an [ArgumentError] if [id] isn't resolved according to
  /// [Source.isResolved]. If there's already an ID with the same name as [id]
  /// in the LockFile, it's overwritten.
  LockFile setPackage(PackageId id) {
    if (id.isRoot) return this;

    if (!_sources[id.source].isResolved(id)) {
      throw new ArgumentError('ID "$id" is not resolved.');
    }

    var packages = new Map.from(this.packages);
    packages[id.name] = id;
    return new LockFile._(packages, _sources);
  }

  /// Returns a copy of this LockFile with a package named [name] removed.
  ///
  /// Returns an identical [LockFile] if there's no package named [name].
  LockFile removePackage(String name) {
    if (!this.packages.containsKey(name)) return this;

    var packages = new Map.from(this.packages);
    packages.remove(name);
    return new LockFile._(packages, _sources);
  }

  /// Returns the contents of the `.packages` file generated from this lockfile.
  ///
  /// If [entrypoint] is passed, a relative entry is added for its "lib/"
  /// directory.
  String packagesFile([String entrypoint]) {
    var header = "Generated by pub on ${new DateTime.now()}.";

    var map = new Map.fromIterable(ordered(packages.keys), value: (name) {
      var id = packages[name];
      var source = _sources[id.source];
      return p.toUri(p.join(source.getDirectory(id), "lib"));
    });

    if (entrypoint != null) map[entrypoint] = Uri.parse("lib/");

    var text = new StringBuffer();
    packages_file.write(text, map, comment: header);
    return text.toString();
  }

  /// Returns the serialized YAML text of the lock file.
  ///
  /// [packageDir] is the containing directory of the root package, used to
  /// properly serialize package descriptions.
  String serialize(String packageDir) {
    // Convert the dependencies to a simple object.
    var data = {};
    packages.forEach((name, package) {
      var description = _sources[package.source]
          .serializeDescription(packageDir, package.description);

      data[name] = {
        'version': package.version.toString(),
        'source': package.source,
        'description': description
      };
    });

    return """
# Generated by pub
# See http://pub.dartlang.org/doc/glossary.html#lockfile
${yamlToString({'packages': data})}
""";
  }
}
