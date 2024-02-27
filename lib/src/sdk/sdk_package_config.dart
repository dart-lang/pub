// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The top level structure of an `sdk_packages.yaml` file.
class SdkPackageConfig {
  /// The name of the SDK this configuration is for.
  ///
  /// SDKs should validate the config is for them on load.
  final String sdk;

  /// All the packages vendored by this SDK.
  final List<SdkPackage> packages;

  SdkPackageConfig(this.sdk, this.packages);

  // Note: yaml has `Object?` keys.
  SdkPackageConfig.fromMap(Map<Object?, Object?> map)
      : sdk = map['sdk'] as String,
        packages = [
          for (var package in map['packages'] as List<Object?>)
            SdkPackage.fromMap(package as Map<Object?, Object?>),
        ];

  Map<String, Object?> toMap() => {
        'sdk': sdk,
        'packages': [
          for (var package in packages) package.toMap(),
        ],
      };
}

/// The structure for each `packages` entry in an `sdk_packages.yaml` file.
class SdkPackage {
  /// The name of the package.
  final String name;

  /// The path to the root of this package relative to the root of the SDK.
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
