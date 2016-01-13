// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

  /// The intersection of all SDK constraints for all locked packages.
  final VersionConstraint sdkConstraint;

  /// Creates a new lockfile containing [ids].
  ///
  /// If passed, [sdkConstraint] represents the intersection of all SKD
  /// constraints for all locked packages. It defaults to
  /// [VersionConstraint.any].
  LockFile(Iterable<PackageId> ids, SourceRegistry sources,
          {VersionConstraint sdkConstraint})
      : this._(
          new Map.fromIterable(
              ids.where((id) => !id.isRoot),
              key: (id) => id.name),
          sdkConstraint ?? VersionConstraint.any,
          sources);

  LockFile._(Map<String, PackageId> packages, this.sdkConstraint, this._sources)
      : packages = new UnmodifiableMapView(packages);

  LockFile.empty(this._sources)
      : packages = const {},
        sdkConstraint = VersionConstraint.any;

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
    if (contents.trim() == '') return new LockFile.empty(sources);

    var sourceUrl;
    if (filePath != null) sourceUrl = p.toUri(filePath);
    var parsed = loadYamlNode(contents, sourceUrl: sourceUrl);

    _validate(parsed is Map, 'The lockfile must be a YAML mapping.', parsed);

    var sdkConstraint = VersionConstraint.any;
    var sdkConstraintText = parsed['sdk'];
    if (sdkConstraintText != null) {
      _validate(
          sdkConstraintText is String,
          'The "sdk" field must be a string.',
          parsed.nodes['sdk']);

      sdkConstraint = _wrapFormatException(
          'version constraint',
          parsed.nodes['sdk'].span,
          () => new VersionConstraint.parse(sdkConstraintText));
    }

    var packages = {};
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
        var id;
        try {
          id = source.parseId(name, version, description);
        } on FormatException catch (ex) {
          throw new SourceSpanFormatException(ex.message,
              spec.nodes['description'].span);
        }

        // Validate the name.
        _validate(name == id.name,
            "Package name $name doesn't match ${id.name}.", spec);

        packages[name] = id;
      });
    }

    return new LockFile._(packages, sdkConstraint, sources);
  }

  /// Runs [fn] and wraps any [FormatException] it throws in a
  /// [SourceSpanFormatException].
  ///
  /// [description] should be a noun phrase that describes whatever's being
  /// parsed or processed by [fn]. [span] should be the location of whatever's
  /// being processed within the pubspec.
  static _wrapFormatException(String description, SourceSpan span, fn()) {
    try {
      return fn();
    } on FormatException catch (e) {
      throw new SourceSpanFormatException(
          'Invalid $description: ${e.message}', span);
    }
  }

  /// If [condition] is `false` throws a format error with [message] for [node].
  static void _validate(bool condition, String message, YamlNode node) {
    if (condition) return;
    throw new SourceSpanFormatException(message, node.span);
  }

  /// Returns a copy of this LockFile with [id] added.
  ///
  /// If there's already an ID with the same name as [id] in the LockFile, it's
  /// overwritten.
  LockFile setPackage(PackageId id) {
    if (id.isRoot) return this;

    var packages = new Map.from(this.packages);
    packages[id.name] = id;
    return new LockFile._(packages, sdkConstraint, _sources);
  }

  /// Returns a copy of this LockFile with a package named [name] removed.
  ///
  /// Returns an identical [LockFile] if there's no package named [name].
  LockFile removePackage(String name) {
    if (!this.packages.containsKey(name)) return this;

    var packages = new Map.from(this.packages);
    packages.remove(name);
    return new LockFile._(packages, sdkConstraint, _sources);
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
    var packageMap = {};
    packages.forEach((name, package) {
      var description = _sources[package.source]
          .serializeDescription(packageDir, package.description);

      packageMap[name] = {
        'version': package.version.toString(),
        'source': package.source,
        'description': description
      };
    });

    var data = {'sdk': sdkConstraint.toString(), 'packages': packageMap};
    return """
# Generated by pub
# See http://pub.dartlang.org/doc/glossary.html#lockfile
${yamlToString(data)}
""";
  }
}
