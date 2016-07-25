// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'io.dart';

/// Whether the Flutter SDK is available.
final bool isAvailable = Platform.environment.containsKey("FLUTTER_ROOT");

/// The path to the root directory of the Flutter SDK.
final String rootDirectory = Platform.environment["FLUTTER_ROOT"];

/// The Flutter SDK's version number, or `null` if the Flutter SDK is
/// unavailable.
final version = () {
  if (!isAvailable) return null;

  return new Version.parse(
      readTextFile(p.join(rootDirectory, "version")).trim());
}();

/// Returns the path to the package [name] within Flutter.
String packagePath(String name) {
  if (!isAvailable) throw new StateError("Flutter is not available.");

  return p.join(rootDirectory, 'packages', name);
}
