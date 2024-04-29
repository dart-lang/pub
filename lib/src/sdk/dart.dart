// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../io.dart';
import '../sdk.dart';
import 'sdk_package_config.dart';

/// The Dart SDK.
///
/// Unlike other SDKs, this is always available.
class DartSdk extends Sdk {
  @override
  String get name => 'Dart';
  @override
  bool get isAvailable => true;
  @override
  String? get installMessage => null;
  @override
  bool get allowsNonSdkDepsInSdkPackages => false;

  static final String _rootDirectory = () {
    // If DART_ROOT is specified, then this always points to the Dart SDK
    if (Platform.environment['DART_ROOT'] case final root?) {
      return root;
    }

    if (runningFromDartRepo) return p.join(dartRepoRoot, 'sdk');

    // The Dart executable is in "/path/to/sdk/bin/dart", so two levels up is
    // "/path/to/sdk".
    final aboveExecutable = p.dirname(p.dirname(Platform.resolvedExecutable));
    assert(fileExists(p.join(aboveExecutable, 'version')));
    return aboveExecutable;
  }();

  /// The loaded `sdk_packages.yaml` file if present.
  static final SdkPackageConfig? _sdkPackages = () {
    final path = p.join(_rootDirectory, 'sdk_packages.yaml');
    if (!fileExists(path)) return null;
    final text = readTextFile(path);
    final yaml = loadYaml(text) as YamlMap;
    final config = SdkPackageConfig.fromYaml(yaml);
    if (config.sdk != 'dart') {
      throw FormatException(
        'Expected a configuration for the `dart` sdk but got one for '
        '`${config.sdk}`.',
        text,
        (yaml.nodes['sdk']!).span.start.offset,
      );
    }
    return config;
  }();

  @override
  final Version version = () {
    // Some of the pub integration tests require an SDK version number, but the
    // tests on the bots are not run from a built SDK so this lets us avoid
    // parsing the missing version file.
    final sdkVersion = Platform.environment['_PUB_TEST_SDK_VERSION'] ??
        Platform.version.split(' ').first;

    return Version.parse(sdkVersion);
  }();

  /// The path to the root directory of the SDK.
  ///
  /// Note that if pub is running from source within the Dart repo (for example
  /// when building Observatory), this will be the repo's "sdk/" directory,
  /// which doesn't look exactly like the built SDK.
  String get rootDirectory => _rootDirectory;

  @override
  String? packagePath(String name) {
    if (!isAvailable) return null;
    final sdkPackages = _sdkPackages;
    if (sdkPackages == null) return null;

    final package = sdkPackages.packages[name];
    if (package == null) return null;
    final packagePath = p.joinAll([_rootDirectory, ...package.path.split('/')]);
    if (dirExists(packagePath)) return packagePath;

    return null;
  }
}
