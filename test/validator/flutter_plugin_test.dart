// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/flutter_plugin.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator flutterPlugin(Entrypoint entrypoint) =>
    FlutterPluginValidator(entrypoint);

main() {
  group('should consider a package valid if it', () {
    setUp(d.validPackage.create);

    test('looks normal', () => expectNoValidationError(flutterPlugin));

    test('is a Flutter 1.9.0 package', () async {
      var pkg = packageMap("test_pkg", "1.0.0", {
        "flutter": {"sdk": "flutter"},
      }, {}, {
        "sdk": ">=2.0.0 <3.0.0",
        "flutter": ">=1.9.0 <2.0.0",
      });
      await d.dir(appPath, [d.pubspec(pkg)]).create();
      expectNoValidationError(flutterPlugin);
    });

    test('is a Flutter 1.10.0 package', () async {
      var pkg = packageMap("test_pkg", "1.0.0", {
        "flutter": {"sdk": "flutter"},
      }, {}, {
        "sdk": ">=2.0.0 <3.0.0",
        "flutter": ">=1.10.0 <2.0.0",
      });
      await d.dir(appPath, [d.pubspec(pkg)]).create();
      expectNoValidationError(flutterPlugin);
    });

    test('is a flutter 1.10.0 plugin with the new format', () async {
      var pkg = packageMap("test_pkg", "1.0.0", {
        "flutter": {"sdk": "flutter"},
      }, {}, {
        "sdk": ">=2.0.0 <3.0.0",
        "flutter": ">=1.10.0 <2.0.0",
      });
      pkg['flutter'] = {
        'plugin': {
          'platforms': {
            'ios': {
              'classPrefix': 'FLT',
              'pluginClass': 'SamplePlugin',
            },
          },
        },
      };
      await d.dir(appPath, [d.pubspec(pkg)]).create();
      expectNoValidationError(flutterPlugin);
    });
  });

  group('should consider a package invalid if it', () {
    setUp(d.validPackage.create);

    test('is a flutter plugin with old and new format', () async {
      var pkg = packageMap("test_pkg", "1.0.0", {
        "flutter": {"sdk": "flutter"},
      }, {}, {
        "sdk": ">=2.0.0 <3.0.0",
        "flutter": ">=1.9.0 <2.0.0",
      });
      pkg['flutter'] = {
        'plugin': {
          'androidPackage': 'io.flutter.plugins.myplugin',
          'iosPrefix': 'FLT',
          'pluginClass': 'MyPlugin',
          'platforms': {
            'ios': {
              'classPrefix': 'FLT',
              'pluginClass': 'SamplePlugin',
            },
          },
        },
      };
      await d.dir(appPath, [d.pubspec(pkg)]).create();
      expectValidationError(flutterPlugin);
    });

    test('is a flutter 1.9.0 plugin with old format', () async {
      var pkg = packageMap("test_pkg", "1.0.0", {
        "flutter": {"sdk": "flutter"},
      }, {}, {
        "sdk": ">=2.0.0 <3.0.0",
        "flutter": ">=1.9.0 <2.0.0",
      });
      pkg['flutter'] = {
        'plugin': {
          'androidPackage': 'io.flutter.plugins.myplugin',
          'iosPrefix': 'FLT',
          'pluginClass': 'MyPlugin',
        },
      };
      await d.dir(appPath, [d.pubspec(pkg)]).create();
      expectValidationWarning(flutterPlugin);
    });

    test('is a flutter 1.9.0 plugin with new format', () async {
      var pkg = packageMap("test_pkg", "1.0.0", {
        "flutter": {"sdk": "flutter"},
      }, {}, {
        "sdk": ">=2.0.0 <3.0.0",
        "flutter": ">=1.9.0 <2.0.0",
      });
      pkg['flutter'] = {
        'plugin': {
          'platforms': {
            'ios': {
              'classPrefix': 'FLT',
              'pluginClass': 'SamplePlugin',
            },
          },
        },
      };
      await d.dir(appPath, [d.pubspec(pkg)]).create();
      expectValidationError(flutterPlugin);
    });
  });
}
