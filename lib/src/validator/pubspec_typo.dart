// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../dice_coefficient.dart';
import '../entrypoint.dart';
import '../validator.dart';

/// Validates that a package's pubspec does not contain any typos in its keys.
class PubspecTypoValidator extends Validator {
  PubspecTypoValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate() async {
    final fields = entrypoint.root.pubspec.fields;

    if (fields == null) return;

    for (final key in fields.keys) {
      var bestDiceCoefficient = 0.0;
      var closestKey = '';

      for (final validKey in _validPubspecKeys) {
        final dice = diceCoefficient(key, validKey);
        if (dice > bestDiceCoefficient) {
          bestDiceCoefficient = dice;
          closestKey = validKey;
        }
      }

      // 0.73 is a magic value determined by looking at the most common typos
      // in all the pubspecs on pub.dev.
      if (bestDiceCoefficient >= 0.73 && bestDiceCoefficient < 1.0) {
        errors.add('$key is not a key recognizable by pub - '
            'did you mean $closestKey?');
      }
    }
  }
}

/// List of keys in `pubspec.yaml` that will be recognized by pub.
///
/// Retrieved from https://dart.dev/tools/pub/pubspec
const _validPubspecKeys = [
  'name',
  'version',
  'description',
  'homepage',
  'repository',
  'issue_tracker',
  'documentation',
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
  'environment',
  'executables',
  'publish_to',
  'flutter'
];
