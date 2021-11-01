// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../entrypoint.dart';
import '../validator.dart';

const _pluginDocsUrl =
    'https://flutter.dev/docs/development/packages-and-plugins/developing-packages#plugin';

/// Validates that Flutter plugins doesn't use both new and old plugin format.
///
/// Warns if using the old plugin registration format.
///
/// See:
/// https://flutter.dev/docs/development/packages-and-plugins/developing-packages
class FlutterPluginFormatValidator extends Validator {
  FlutterPluginFormatValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate() async {
    final pubspec = entrypoint.root.pubspec;

    // Ignore all packages that do not have the `flutter.plugin` property.
    if (pubspec.fields['flutter'] is! Map ||
        pubspec.fields['flutter']['plugin'] is! Map) {
      return;
    }
    final plugin = pubspec.fields['flutter']['plugin'] as Map;

    // Determine if this uses the old format by checking if `flutter.plugin`
    // contains any of the following keys.
    final usesOldPluginFormat = const {
      'androidPackage',
      'iosPrefix',
      'pluginClass',
    }.any(plugin.containsKey);

    // Determine if this uses the new format by check if the:
    // `flutter.plugin.platforms` keys is defined.
    final usesNewPluginFormat = plugin['platforms'] != null;

    // If the new plugin format is used, and the flutter SDK dependency allows
    // SDKs older than 1.10.0, then this is going to be a problem.
    final flutterConstraint = pubspec.sdkConstraints['flutter'];
    if (usesNewPluginFormat &&
        (flutterConstraint == null ||
            flutterConstraint.allowsAny(VersionRange(
              min: Version.parse('0.0.0'),
              max: Version.parse('1.10.0'),
              includeMin: true,
            )))) {
      errors.add('pubspec.yaml allows Flutter SDK version 1.9.x, which does '
          'not support the flutter.plugin.platforms key.\n'
          'Please consider increasing the Flutter SDK requirement to '
          '^1.10.0 (environment.sdk.flutter)\n\nSee $_pluginDocsUrl');
      return;
    }

    if (usesOldPluginFormat) {
      errors.add('In pubspec.yaml the '
          'flutter.plugin.{androidPackage,iosPrefix,pluginClass} keys are '
          'deprecated. Instead use the flutter.plugin.platforms key '
          'introduced in Flutter 1.10.0\n\nSee $_pluginDocsUrl');
    }
  }
}
