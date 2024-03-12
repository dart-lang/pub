// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async' show Future;
import 'dart:convert' show JsonEncoder, json;
import 'dart:io' show File;

import 'package:path/path.dart' as p;
import 'package:pub/src/package_config.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart';

/// Describes a `.dart_tools/package_config.json` file and its contents.
class PackageConfigFileDescriptor extends Descriptor {
  final String _generatorVersion;
  final String _pubCache;
  final String? _flutterRoot;
  final String? _flutterVersion;

  /// A map describing the packages in this `package_config.json` file.
  final List<PackageConfigEntry> _packages;

  PackageConfig _config(String? parent) {
    return PackageConfig(
      path:
          p.join(parent ?? sandbox, name, '.dart_tool', 'package_config.json'),
      configVersion: 2,
      packages: _packages,
      generatorVersion: Version.parse(_generatorVersion),
      generator: 'pub',
      generated: DateTime.now().toUtc(),
      additionalProperties: {
        'pubCache': p.toUri(_pubCache).toString(),
        if (_flutterRoot != null)
          'flutterRoot': p.toUri(_flutterRoot).toString(),
        if (_flutterVersion != null) 'flutterVersion': _flutterVersion,
      },
    );
  }

  /// Describes a `.dart_tools/package_config.json` file
  /// with the given list of package configurations and
  /// generated with specified version.
  PackageConfigFileDescriptor(
    this._packages,
    this._generatorVersion,
    this._pubCache,
    this._flutterRoot,
    this._flutterVersion,
  ) : super('.dart_tool/package_config.json');

  @override
  Future<void> create([String? parent]) async {
    final packageConfigFile = File(p.join(parent ?? sandbox, name));
    await packageConfigFile.parent.create();
    await packageConfigFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(_config(parent).toJson())}\n',
    );
  }

  @override
  Future<void> validate([String? parent]) async {
    final packageConfigFile = p.join(parent ?? sandbox, name);
    if (!await File(packageConfigFile).exists()) {
      fail("File not found: '$packageConfigFile'.");
    }

    final rawJson = json.decode(await File(packageConfigFile).readAsString());
    PackageConfig config;
    try {
      config = PackageConfig.fromJson(packageConfigFile, rawJson);
    } on FormatException catch (e) {
      fail('File "$packageConfigFile" is not valid: $e');
    }

    // Compare packages as sets to ignore ordering.
    expect(
      config.packages,
      _packages
          .map(
            (p) => isA<PackageConfigEntry>()
                .having((p0) => p0.name, 'name', p.name)
                .having(
                  (p0) => p0.languageVersion,
                  'languageVersion',
                  // If the expected entry has no language-version we don't check it.
                  p.languageVersion ?? anything,
                )
                .having((p0) => p0.rootUri, 'rootUri', p.rootUri)
                .having((p0) => p0.packageUri, 'packageUri', p.packageUri),
          )
          .toSet(),
    );

    final expected =
        PackageConfig.fromJson(packageConfigFile, _config(parent).toJson());
    // omit generated date-time and packages
    expected.generated = null; // comparing timestamps is unnecessary.
    config.generated = null;
    expected.packages = []; // Already compared packages (ignoring ordering)
    config.packages = [];
    expect(
      config.toJson(),
      equals(expected.toJson()),
      reason: '"$packageConfigFile" does not match expected values',
    );
  }

  @override
  String describe() => name;
}
