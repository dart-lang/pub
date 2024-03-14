// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The top level structure of an `sdk_packages.yaml` file.
///
/// See https://github.com/dart-lang/pub/issues/3980 for discussion of the
/// format.
class SdkPackageConfig {
  /// The name of the SDK this configuration is for.
  ///
  /// SDKs should validate the config is for them on load, and this is the only
  /// real use for this field.
  final String sdk;

  /// All the packages vendored by this SDK.
  final Map<String, SdkPackage> packages;

  /// The version of the format.
  final int version;

  SdkPackageConfig(this.sdk, this.packages, this.version);

  // Note: yaml has `Object?` keys.
  //
  // TODO: Add more friendly validation messages here as opposed to just casts.
  factory SdkPackageConfig.fromMap(Map<Object?, Object?> map) {
    final version = map['version'] as int;
    if (version != 1) {
      throw UnsupportedError('This SDK only supports version 1 of the '
          'sdk_packages.yaml format, but got version $version');
    }
    final packages = <String, SdkPackage>{};
    for (var entry in map['packages'] as List<Object?>) {
      final package = SdkPackage.fromMap(entry as Map<Object?, Object?>);
      packages[package.name] = package;
    }

    return SdkPackageConfig(
      map['sdk'] as String,
      packages,
      version,
    );
  }

  Map<String, Object?> toMap() => {
        'sdk': sdk,
        'packages': [
          for (var package in packages.values) package.toMap(),
        ],
        'version': version,
      };
}

/// The structure for each `packages` entry in an `sdk_packages.yaml` file.
class SdkPackage {
  /// The name of the package.
  final String name;

  /// The path to the root of this package relative to the root of the installed
  /// SDK.
  ///
  /// This path should be in URL format (with forward slashes), and always
  /// relative.
  final String path;

  SdkPackage(this.name, this.path);

  // Note: yaml has `Object?` keys.
  SdkPackage.fromMap(Map<Object?, Object?> map)
      : name = map['name'] as String,
        path = map['path'] as String;

  Map<String, Object?> toMap() => {
        'name': name,
        'path': path,
      };
}
