// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/validator.dart';
import 'package:pub/src/validator/flutter_plugin_format.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

Validator flutterPluginFormat(Entrypoint entrypoint) =>
    FlutterPluginFormatValidator(entrypoint);

void main() {
  group('should consider a package valid if it', () {
    test('is not a plugin', () async {
      await d.validPackage.create();
      return expectValidation(flutterPluginFormat);
    });

    test('is a Flutter 1.9.0 package', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.9.0 <2.0.0',
      });
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(flutterPluginFormat);
    });

    test('is a Flutter 1.10.0 package', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.10.0 <2.0.0',
      });
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(flutterPluginFormat);
    });

    test('is a Flutter 1.10.0-0 package', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.10.0-0 <2.0.0',
      });
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(flutterPluginFormat);
    });

    test('is a flutter 1.10.0 plugin with the new format', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.10.0 <2.0.0',
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
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(flutterPluginFormat);
    });
  });

  group('should consider a package invalid if it', () {
    test('is a flutter plugin with old and new format', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.9.0 <2.0.0',
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
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(
        flutterPluginFormat,
        errors: contains(
          contains(
              'Please consider increasing the Flutter SDK requirement to ^1.10.0'),
        ),
      );
    });

    test('is a flutter 1.9.0 plugin with old format', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.9.0 <2.0.0',
      });
      pkg['flutter'] = {
        'plugin': {
          'androidPackage': 'io.flutter.plugins.myplugin',
          'iosPrefix': 'FLT',
          'pluginClass': 'MyPlugin',
        },
      };
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(flutterPluginFormat,
          errors: contains(
            contains('Instead use the flutter.plugin.platforms key'),
          ));
    });

    test('is a flutter 1.9.0 plugin with new format', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.9.0 <2.0.0',
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
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(
        flutterPluginFormat,
        errors: contains(
          contains(
              'Please consider increasing the Flutter SDK requirement to ^1.10.0'),
        ),
      );
    });

    test(
        'is a flutter plugin with only implicit flutter sdk version constraint and the new format',
        () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
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
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(
        flutterPluginFormat,
        errors: contains(
          contains(
              'Please consider increasing the Flutter SDK requirement to ^1.10.0'),
        ),
      );
    });

    test('is a non-flutter package with using the new format', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {}, {}, {
        'sdk': '>=2.0.0 <3.0.0',
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
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(
        flutterPluginFormat,
        errors: contains(
          contains(
              'Please consider increasing the Flutter SDK requirement to ^1.10.0'),
        ),
      );
    });

    test('is a flutter 1.8.0 plugin with new format', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.8.0 <2.0.0',
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
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(flutterPluginFormat,
          errors: contains(
            contains(
                'Please consider increasing the Flutter SDK requirement to ^1.10.0'),
          ));
    });

    test('is a flutter 1.9.999 plugin with new format', () async {
      var pkg = packageMap('test_pkg', '1.0.0', {
        'flutter': {'sdk': 'flutter'},
      }, {}, {
        'sdk': '>=2.0.0 <3.0.0',
        'flutter': '>=1.9.999 <2.0.0',
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
      await d.dir(appPath, [d.pubspec(pkg), d.dir('ios')]).create();
      await expectValidation(flutterPluginFormat,
          errors: contains(
            contains(
                'Please consider increasing the Flutter SDK requirement to ^1.10.0'),
          ));
    });
  });
}
