// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../validator.dart';

/// Validates that a package's flutter constraint doesn't contain an upper bound
class FlutterConstraintValidator extends Validator {
  static const explanationUrl =
      'https://dart.dev/go/flutter-upper-bound-deprecation';

  @override
  Future validate() async {
    final environment = entrypoint.root.pubspec.fields['environment'];
    if (environment is Map) {
      final flutterConstraint = environment['flutter'];
      if (flutterConstraint is String) {
        final constraint = VersionConstraint.parse(flutterConstraint);
        if (constraint is VersionRange && constraint.max != null) {
          final replacement = constraint.min == null
              ? 'You can replace the constraint with `any`.'
              : 'You can replace that with just the lower bound: `>=${constraint.min}`.';

          warnings.add('''
The Flutter constraint should not have an upper bound.
In your pubspec.yaml the constraint is currently `$flutterConstraint`.

$replacement

See $explanationUrl''');
        }
      }
    }
  }
}
