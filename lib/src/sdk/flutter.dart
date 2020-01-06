// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../io.dart';
import '../sdk.dart';

class FlutterSdk extends Sdk {
  @override
  String get name => 'Flutter';
  @override
  bool get isAvailable => _isAvailable;
  @override
  Version get firstPubVersion => Version.parse('1.19.0');

  static final bool _isAvailable =
      Platform.environment.containsKey('FLUTTER_ROOT');
  static final String _rootDirectory = Platform.environment['FLUTTER_ROOT'];

  @override
  String get installMessage =>
      'Flutter users should run `flutter pub get` instead of `pub get`.';

  @override
  Version get version {
    if (!_isAvailable) return null;

    _version ??=
        Version.parse(readTextFile(p.join(_rootDirectory, 'version')).trim());
    return _version;
  }

  Version _version;

  @override
  String packagePath(String name) {
    if (!isAvailable) return null;

    // Flutter packages exist in both `$flutter/packages` and
    // `$flutter/bin/cache/pkg`. This checks both locations in order. If [name]
    // exists in neither place, it returns the `$flutter/packages` location
    // which is more human-readable for error messages.
    var packagePath = p.join(_rootDirectory, 'packages', name);
    if (dirExists(packagePath)) return packagePath;

    var cachePath = p.join(_rootDirectory, 'bin', 'cache', 'pkg', name);
    if (dirExists(cachePath)) return cachePath;

    return null;
  }
}
