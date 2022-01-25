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

  // We only consider the Flutter SDK to present if we find a root directory
  // and the root directory contains a valid 'version' file.
  static final bool _isAvailable = _rootDirectory != null && _version != null;
  static final String? _rootDirectory = () {
    // If FLUTTER_ROOT is specified, then this always points to the Flutter SDK
    if (Platform.environment.containsKey('FLUTTER_ROOT')) {
      return Platform.environment['FLUTTER_ROOT'];
    }

    // We can try to find the Flutter SDK relative to the Dart SDK.
    // We know that the Dart SDK is always present, this is found relative to
    // the `dart` executable, for details see: lib/src/sdk/dart.dart
    //
    // Once we have the location of the Dart SDK, we can look at its parent
    // directories, if going 3 levels-up and down `bin/cache/dart-sdk/` is equal
    // to the Dart SDK root, then it's probably because we are located inside
    // the Flutter SDK, at: `$FLUTTER_ROOT/bin/cache/dart-sdk`
    final parts = p.split(sdk.rootDirectory);
    if (parts.length > 3) {
      // Go 3-levels up from the Dart SDK root
      final flutterSdk = p.joinAll(parts.take(parts.length - 3));
      // If going down 'bin/cache/dart-sdk/' yields the same path as the Dart
      // SDK has, then it's probably because the Dart SDK is located inside
      // the Flutter SDK.
      final dartRootFromFlutterSdk = p.join(
        flutterSdk,
        'bin',
        'cache',
        'dart-sdk',
      );
      if (p.equals(sdk.rootDirectory, dartRootFromFlutterSdk)) {
        return flutterSdk;
      }
    }

    return null;
  }();
  static final Version? _version = () {
    if (_rootDirectory == null) return null;

    try {
      return Version.parse(
        readTextFile(p.join(_rootDirectory!, 'version')).trim(),
      );
    } on IOException {
      return null; // I guess the file doesn't exist
    } on FormatException {
      return null; // I guess the file has the wrong format
    }
  }();

  @override
  String get installMessage =>
      'Flutter users should run `flutter pub get` instead of `dart pub get`.';

  @override
  Version? get version {
    if (!isAvailable) return null;
    return _version;
  }

  @override
  String? packagePath(String name) {
    if (!isAvailable) return null;

    // Flutter packages exist in both `$flutter/packages` and
    // `$flutter/bin/cache/pkg`. This checks both locations in order. If [name]
    // exists in neither place, it returns the `$flutter/packages` location
    // which is more human-readable for error messages.
    var packagePath = p.join(_rootDirectory!, 'packages', name);
    if (dirExists(packagePath)) return packagePath;

    var cachePath = p.join(_rootDirectory!, 'bin', 'cache', 'pkg', name);
    if (dirExists(cachePath)) return cachePath;

    return null;
  }
}
