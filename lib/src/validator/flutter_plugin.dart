// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../entrypoint.dart';
import '../validator.dart';

/// Validates that Flutter plugins doesn't use both new and old plugin format.
///
/// Warns if using the old plugin registration format.
class FlutterPluginValidator extends Validator {
  FlutterPluginValidator(Entrypoint entrypoint) : super(entrypoint);

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
    final usesOldPluginRegistrationFormat = {
      'androidPackage',
      'iosPrefix',
      'pluginClass',
    }.any(plugin.containsKey);

    // Determine if this uses the new format by check if the:
    // `flutter.plugin.platforms` keys is defined.
    final usesNewPluginRegistrationFormat = plugin['platforms'] != null;

    // Report an error, if both the new and the old format is used.
    if (usesOldPluginRegistrationFormat && usesNewPluginRegistrationFormat) {
      errors.add('In pubspec.yaml the flutter.plugin.platforms plugin '
          'registration format, cannot be used in combination with the old '
          'flutter.plugin.{androidPackage,iosPrefix,pluginClass} '
          'plugin registration format.');
    }

    // If the new plugin format is used, and the flutter SDK dependency allows
    // SDKs older than 1.12, then this is going to be a problem.
    if (usesNewPluginRegistrationFormat &&
        !pubspec.sdkConstraints['flutter'].allows(Version.parse('1.11'))) {
      warnings.add('pubspec.yaml allows Flutter SDK version 1.11, which does '
          'not support the flutter.plugin.platforms plugin registration '
          'format. Please consider increasing the Flutter SDK requirement to '
          '^1.12 (environment.sdk.flutter)');
    }

    // Warn if using the old plugin registration format.
    if (usesOldPluginRegistrationFormat) {
      warnings.add('The flutter.plugin.{androidPackage,iosPrefix,pluginClass} '
          'plugin registration format is deprecated. Consider using the '
          'flutter.plugin.platforms plugin registration format introduced in '
          'Flutter 1.12');
    }
  }
}
