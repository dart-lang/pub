// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async' show Future;
import 'dart:convert' show JsonEncoder, json, utf8;
import 'dart:io' show File;

// ignore: deprecated_member_use
import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;
import 'package:pub/src/package_config.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart';

import '../test_pub.dart';

// Resolve against a dummy URL so that we can test whether the URLs in
// the package file are themselves relative. We can't resolve against just
// "." due to sdk#23809.
const _base = '/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p';

/// Describes a `.packages` file and its contents.
class PackagesFileDescriptor extends Descriptor {
  /// A map from package names to either version strings or path to the package.
  final Map<String, String> _dependencies;

  /// Describes a `.packages` file with the given dependencies.
  ///
  /// [dependencies] maps package names to strings describing where the packages
  /// are located on disk.
  PackagesFileDescriptor([this._dependencies]) : super('.packages');

  @override
  Future create([String parent]) {
    var contents = const <int>[];
    if (_dependencies != null) {
      var mapping = <String, Uri>{};
      _dependencies.forEach((package, version) {
        String packagePath;
        if (_isSemver(version)) {
          // It's a cache reference.
          packagePath = p.join(cachePath, '$package-$version');
        } else {
          // Otherwise it's a path relative to the pubspec file,
          // which is also relative to the .packages file.
          packagePath = version;
        }
        mapping[package] = p.toUri(p.join(packagePath, 'lib', ''));
      });
      var buffer = StringBuffer();
      packages_file.write(buffer, mapping);
      contents = utf8.encode(buffer.toString());
    }
    return File(p.join(parent ?? sandbox, name)).writeAsBytes(contents);
  }

  @override
  Future validate([String parent]) async {
    var fullPath = p.join(parent ?? sandbox, name);
    if (!await File(fullPath).exists()) {
      fail("File not found: '$fullPath'.");
    }

    var bytes = await File(fullPath).readAsBytes();

    var map = packages_file.parse(bytes, Uri.parse(_base));

    for (var package in _dependencies.keys) {
      if (!map.containsKey(package)) {
        fail('.packages does not contain $package entry');
      }

      var description = _dependencies[package];
      if (_isSemver(description)) {
        if (!map[package].path.contains(description)) {
          fail('.packages of $package has incorrect version. '
              'Expected $description, found location: ${map[package]}.');
        }
      } else {
        var expected = p.normalize(p.join(description, 'lib'));
        var actual = p.normalize(p.fromUri(
            p.url.relative(map[package].toString(), from: p.dirname(_base))));

        if (expected != actual) {
          fail('Relative path: Expected $expected, found $actual');
        }
      }
    }

    if (map.length != _dependencies.length) {
      for (var key in map.keys) {
        if (!_dependencies.containsKey(key)) {
          fail('.packages file contains unexpected entry: $key');
        }
      }
    }
  }

  @override
  String describe() => name;
}

/// Describes a `.dart_tools/package_config.json` file and its contents.
class PackageConfigFileDescriptor extends Descriptor {
  /// A map describing the packages in this `package_config.json` file.
  final List<PackageConfigEntry> _packages;

  PackageConfig get _config {
    return PackageConfig(
      configVersion: 2,
      packages: _packages,
      generatorVersion: Version.parse('0.1.2+3'),
      generator: 'pub',
      generated: DateTime.now().toUtc(),
    );
  }

  /// Describes a `.packages` file with the given dependencies.
  ///
  /// [dependencies] maps package names to strings describing where the packages
  /// are located on disk.
  PackageConfigFileDescriptor(this._packages)
      : super('.dart_tool/package_config.json');

  @override
  Future<void> create([String parent]) async {
    final packageConfigFile = File(p.join(parent ?? sandbox, name));
    await packageConfigFile.parent.create();
    await packageConfigFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_config.toJson()) + '\n',
    );
  }

  @override
  Future<void> validate([String parent]) async {
    final packageConfigFile = p.join(parent ?? sandbox, name);
    if (!await File(packageConfigFile).exists()) {
      fail("File not found: '$packageConfigFile'.");
    }

    Map<String, Object> rawJson = json.decode(
      await File(packageConfigFile).readAsString(),
    );
    PackageConfig config;
    try {
      config = PackageConfig.fromJson(rawJson);
    } on FormatException catch (e) {
      fail('File "$packageConfigFile" is not valid: $e');
    }

    // Compare packages as sets to ignore ordering.
    expect(
      config.packages.map((e) => e.toJson()).toSet(),
      equals(_packages.map((e) => e.toJson()).toSet()),
      reason:
          '"packages" property in "$packageConfigFile" does not expected values',
    );

    final expected = PackageConfig.fromJson(_config.toJson());
    // omit generated date-time and packages
    expected.generated = null; // comparing timestamps is unnecessary.
    config.generated = null;
    expected.packages = []; // Already compared packages (ignoring ordering)
    config.packages = [];
    expect(config.toJson(), equals(expected.toJson()),
        reason: '"$packageConfigFile" does not match expected values');
  }

  @override
  String describe() => name;
}

/// Returns `true` if [text] is a valid semantic version number string.
bool _isSemver(String text) {
  try {
    // See if it's a semver.
    Version.parse(text);
    return true;
  } on FormatException catch (_) {
    // Do nothing.
  }
  return false;
}
