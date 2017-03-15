// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../entrypoint.dart';
import '../validator.dart';

/// A validator that validates a package's dependencies overrides (or the
/// absence thereof).
class DependencyOverrideValidator extends Validator {
  DependencyOverrideValidator(Entrypoint entrypoint) : super(entrypoint);

  Future validate() {
    var overridden =
        entrypoint.root.dependencyOverrides.map((dep) => dep.name).toSet();
    var dev = entrypoint.root.devDependencies.map((dep) => dep.name).toSet();
    if (overridden.difference(dev).isNotEmpty) {
      errors.add('Your pubspec.yaml must not override non-dev dependencies.\n'
          'This ensures you test your package against the same versions of '
          'its dependencies\n'
          'that users will have when they use it.');
    }
    return new Future.value();
  }
}
