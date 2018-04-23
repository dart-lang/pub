// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../io.dart';
import '../sdk.dart';

class FuchsiaSdk extends Sdk {
  String get name => "Fuchsia";
  bool get isAvailable => _isAvailable;
  Version get firstPubVersion => new Version.parse('2.0.0-dev.51.0');

  static final bool _isAvailable =
      Platform.environment.containsKey("FUCHSIA_DART_SDK_ROOT");
  static final String _rootDirectory =
      Platform.environment["FUCHSIA_DART_SDK_ROOT"];

  String get installMessage =>
      "Please set the FUCHSIA_DART_SDK_ROOT environment variable to point to "
      "the root of the Fuchsia SDK for Dart.";

  final Version version = () {
    if (!_isAvailable) return null;

    return new Version.parse(
        readTextFile(p.join(_rootDirectory, "version")).trim());
  }();

  String packagePath(String name) {
    if (!isAvailable) return null;

    var packagePath = p.join(_rootDirectory, 'packages', name);
    if (dirExists(packagePath)) return packagePath;

    return null;
  }
}
