// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../io.dart';
import '../sdk.dart';

/// The Dart SDK.
///
/// Unlike other SDKs, this is always available.
class DartSdk extends Sdk {
  @override
  String get name => 'Dart';
  @override
  bool get isAvailable => true;
  @override
  String get installMessage => null;
  @override
  Version get firstPubVersion => Version.none;

  /// The path to the root directory of the SDK.
  ///
  /// Note that if pub is running from source within the Dart repo (for example
  /// when building Observatory), this will be the repo's "sdk/" directory,
  /// which doesn't look exactly like the built SDK.
  static final String _rootDirectory = () {
    if (runningFromDartRepo) return p.join(dartRepoRoot, 'sdk');

    // The Dart executable is in "/path/to/sdk/bin/dart", so two levels up is
    // "/path/to/sdk".
    var aboveExecutable = p.dirname(p.dirname(Platform.resolvedExecutable));
    assert(fileExists(p.join(aboveExecutable, 'version')));
    return aboveExecutable;
  }();

  @override
  final Version version = () {
    // Some of the pub integration tests require an SDK version number, but the
    // tests on the bots are not run from a built SDK so this lets us avoid
    // parsing the missing version file.
    var sdkVersion = Platform.environment['_PUB_TEST_SDK_VERSION'] ??
        Platform.version.split(' ').first;

    return Version.parse(sdkVersion);
  }();

  String get rootDirectory => _rootDirectory;

  @override
  String packagePath(String name) => null;
}
