// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';

import '../entrypoint.dart';
import '../validator.dart';

/// A validator that validates a package's dependencies overrides (or the
/// absence thereof).
class DependencyOverrideValidator extends Validator {
  DependencyOverrideValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate() {
    var overridden = MapKeySet(entrypoint.root.dependencyOverrides);
    var dev = MapKeySet(entrypoint.root.devDependencies);
    if (overridden.difference(dev).isNotEmpty) {
      errors.add('Your pubspec.yaml must not override non-dev dependencies.\n'
          'This ensures you test your package against the same versions of '
          'its dependencies\n'
          'that users will have when they use it.');
    }
    return Future.value();
  }
}
