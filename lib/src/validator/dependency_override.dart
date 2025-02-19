// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';

import '../validator.dart';

/// A validator that validates a package's dependencies overrides (or the
/// absence thereof).
class DependencyOverrideValidator extends Validator {
  @override
  Future<void> validate() async {
    final overridden = MapKeySet(
      context.entrypoint.workspaceRoot.allOverridesInWorkspace,
    );
    final dev = MapKeySet(package.devDependencies);
    if (overridden.difference(dev).isNotEmpty) {
      final overridesFile =
          package.pubspec.dependencyOverridesFromOverridesFile
              ? package.pubspecOverridesPath
              : package.pubspecPath;

      hints.add('''
Non-dev dependencies are overridden in $overridesFile.

This indicates you are not testing your package against the same versions of its
dependencies that users will have when they use it.

This might be necessary for packages with cyclic dependencies.

Please be extra careful when publishing.''');
    }
  }
}
