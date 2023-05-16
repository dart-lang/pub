// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'language_version.dart';

/// Contents of a `.dart_tool/package_config.json` file.
class PackageConfig {
  /// Version of the configuration in the `.dart_tool/package_config.json` file.
  ///
  /// The only supported value as of writing is `2`.
  int configVersion;

  /// Packages configured.
  List<PackageConfigEntry> packages;

  /// Date-time the `.dart_tool/package_config.json` file was generated.
  ///
  /// `null` if not given.
  DateTime? generated;

  /// Tool that generated the `.dart_tool/package_config.json` file.
  ///
  /// For `pub` this is always `'pub'`.
  ///
  /// `null` if not given.
  String? generator;

  /// Version of the tool that generated the `.dart_tool/package_config.json`
  /// file.
  ///
  /// For `pub` this is the Dart SDK version from which `pub get` was called.
  ///
  /// `null` if not given.
  Version? generatorVersion;

  /// Additional properties not in the specification for the
  /// `.dart_tool/package_config.json` file.
  Map<String, dynamic> additionalProperties;

  PackageConfig({
    required this.configVersion,
    required this.packages,
    this.generated,
    this.generator,
    this.generatorVersion,
    Map<String, dynamic>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  /// Create [PackageConfig] from JSON [data].
  ///
  /// Throws [FormatException], if format is invalid, this does not validate the
  /// contents only that the format is correct.
  factory PackageConfig.fromJson(Object data) {
    if (data is! Map<String, dynamic>) {
      throw FormatException('package_config.json must be a JSON object');
    }
    final root = data;

    void throwFormatException(String property, String mustBe) =>
        throw FormatException(
          '"$property" in .dart_tool/package_config.json $mustBe',
        );

    /// Read the 'configVersion' property
    final configVersion = root['configVersion'];
    if (configVersion is! int) {
      throwFormatException('configVersion', 'must be an integer');
    }
    if (configVersion != 2) {
      throwFormatException(
        'configVersion',
        'must be 2 (the only supported version)',
      );
    }

    final packagesRaw = root['packages'];
    if (packagesRaw is! List) {
      throwFormatException('packages', 'must be a list');
    }
    final packages = <PackageConfigEntry>[];
    for (final entry in packagesRaw as List) {
      packages.add(PackageConfigEntry.fromJson(entry as Object));
    }

    // Read the 'generated' property
    DateTime? generated;
    final generatedRaw = root['generated'];
    if (generatedRaw != null) {
      if (generatedRaw is! String) {
        throwFormatException('generated', 'must be a string, if given');
      }
      generated = DateTime.parse(generatedRaw as String);
    }

    // Read the 'generator' property
    final generator = root['generator'];
    if (generator != null && generator is! String) {
      throw FormatException(
        '"generator" in package_config.json must be a string, if given',
      );
    }

    // Read the 'generatorVersion' property
    Version? generatorVersion;
    final generatorVersionRaw = root['generatorVersion'];
    if (generatorVersionRaw != null) {
      if (generatorVersionRaw is! String) {
        throwFormatException('generatorVersion', 'must be a string, if given');
      }
      try {
        generatorVersion = Version.parse(generatorVersionRaw as String);
      } on FormatException catch (e) {
        throwFormatException(
          'generatorVersion',
          'must be a semver version, if given, error: ${e.message}',
        );
      }
    }

    return PackageConfig(
      configVersion: configVersion as int,
      packages: packages,
      generated: generated,
      generator: generator as String?,
      generatorVersion: generatorVersion,
      additionalProperties: Map.fromEntries(
        root.entries.where(
          (e) => !{
            'configVersion',
            'packages',
            'generated',
            'generator',
            'generatorVersion',
          }.contains(e.key),
        ),
      ),
    );
  }

  /// Convert to JSON structure.
  Map<String, Object?> toJson() => {
        'configVersion': configVersion,
        'packages': packages.map((p) => p.toJson()).toList(),
        'generated': generated?.toUtc().toIso8601String(),
        'generator': generator,
        'generatorVersion': generatorVersion?.toString(),
      }..addAll(additionalProperties);

  // We allow the package called 'flutter_gen' to be injected into
  // package_config.
  //
  // This is somewhat a hack. But it allows flutter to generate code in a
  // package as it likes.
  //
  // See https://github.com/flutter/flutter/issues/73870 .
  Iterable<PackageConfigEntry> get nonInjectedPackages =>
      packages.where((package) => !_isInjectedFlutterGenPackage(package));
}

bool _isInjectedFlutterGenPackage(PackageConfigEntry package) =>
    package.name == 'flutter_gen' &&
    package.rootUri.toString() == 'flutter_gen';

class PackageConfigEntry {
  /// Package name.
  String name;

  /// Root [Uri] of the package.
  ///
  /// This specifies the root folder of the package, all files below this folder
  /// is considered part of this package.
  Uri rootUri;

  /// Relative URI path of the library folder relative to [rootUri].
  ///
  /// Import statements in Dart programs are resolved relative to this folder.
  /// This must be in the sub-tree under [rootUri].
  ///
  /// `null` if not given.
  Uri? packageUri;

  /// Language version used by package.
  ///
  /// Given as `<major>.<minor>` version, similar to the `// @dart = X.Y`
  /// comment. This is derived from the lower-bound on the Dart SDK requirement
  /// in the `pubspec.yaml` for the given package.
  LanguageVersion? languageVersion;

  /// Additional properties not in the specification for the
  /// `.dart_tool/package_config.json` file.
  Map<String, dynamic>? additionalProperties;

  PackageConfigEntry({
    required this.name,
    required this.rootUri,
    this.packageUri,
    this.languageVersion,
    this.additionalProperties = const {},
  });

  /// Create [PackageConfigEntry] from JSON [data].
  ///
  /// Throws [FormatException], if format is invalid, this does not validate the
  /// contents only that the format is correct.
  factory PackageConfigEntry.fromJson(Object data) {
    if (data is! Map<String, dynamic>) {
      throw FormatException(
        'packages[] entries in package_config.json must be JSON objects',
      );
    }
    final root = data;

    Never throwFormatException(String property, String mustBe) =>
        throw FormatException(
          '"packages[].$property" in .dart_tool/package_config.json $mustBe',
        );

    final name = root['name'];
    if (name is! String) {
      throwFormatException('name', 'must be a string');
    }

    final Uri rootUri;
    final rootUriRaw = root['rootUri'];
    if (rootUriRaw is! String) {
      throwFormatException('rootUri', 'must be a string');
    }
    try {
      rootUri = Uri.parse(rootUriRaw);
    } on FormatException {
      throwFormatException('rootUri', 'must be a URI');
    }

    Uri? packageUri;
    var packageUriRaw = root['packageUri'];
    if (packageUriRaw != null) {
      if (packageUriRaw is! String) {
        throwFormatException('packageUri', 'must be a string');
      }
      if (!packageUriRaw.endsWith('/')) {
        packageUriRaw = '$packageUriRaw/';
      }
      try {
        packageUri = Uri.parse(packageUriRaw);
      } on FormatException {
        throwFormatException('packageUri', 'must be a URI');
      }
    }

    LanguageVersion? languageVersion;
    final languageVersionRaw = root['languageVersion'];
    if (languageVersionRaw != null) {
      if (languageVersionRaw is! String) {
        throwFormatException('languageVersion', 'must be a string');
      }
      try {
        languageVersion = LanguageVersion.parse(languageVersionRaw);
      } on FormatException {
        throwFormatException(
          'languageVersion',
          'must be on the form <major>.<minor>',
        );
      }
    }

    return PackageConfigEntry(
      name: name,
      rootUri: rootUri,
      packageUri: packageUri,
      languageVersion: languageVersion,
    );
  }

  /// Convert to JSON structure.
  Map<String, Object?> toJson() => {
        'name': name,
        'rootUri': rootUri.toString(),
        if (packageUri != null) 'packageUri': packageUri.toString(),
        if (languageVersion != null) 'languageVersion': '$languageVersion',
      }..addAll(additionalProperties ?? {});

  @override
  String toString() {
    // TODO: implement toString
    return JsonEncoder.withIndent('  ').convert(toJson());
  }

  String resolvedRootDir(String packageConfigPath) {
    return p.join(p.dirname(packageConfigPath), p.fromUri(rootUri));
  }
}
