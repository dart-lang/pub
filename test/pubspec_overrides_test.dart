// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('pubspec overrides in default location',
        () => pubspecOverridesTest(command, PubspecOverridesLocation.default_));

    test(
        'pubspec overrides in default location, but disabled',
        () => pubspecOverridesTest(
            command, PubspecOverridesLocation.defaultDisabled));

    test(
        'pubspec overrides in custom relative location',
        () => pubspecOverridesTest(
            command, PubspecOverridesLocation.customRelative));

    test(
        'pubspec overrides in custom absolute location',
        () => pubspecOverridesTest(
            command, PubspecOverridesLocation.customAbsolute));
  });
}

enum PubspecOverridesLocation {
  default_,
  defaultDisabled,
  customAbsolute,
  customRelative,
}

/// Test to verify the behavior of pubspec overrides files in
/// different locations and with different command line arguments.
Future<void> pubspecOverridesTest(
    RunCommand command, PubspecOverridesLocation location) async {
  await servePackages((builder) {
    builder.serve('lib', '1.0.0');
    builder.serve('lib', '2.0.0');
  });

  var appDirContents = <d.Descriptor>[];
  var overridesDirContents = <d.Descriptor>[];

  // Setup the overrides files.
  switch (location) {
    case PubspecOverridesLocation.default_:
    case PubspecOverridesLocation.defaultDisabled:
      appDirContents.add(d.pubspecOverrides({
        'dependencies': {'lib': '2.0.0'}
      }));
      break;
    case PubspecOverridesLocation.customRelative:
    case PubspecOverridesLocation.customAbsolute:
      overridesDirContents.add(d.pubspecOverrides({
        'dependencies': {'lib': '2.0.0'}
      }, name: 'a.yaml'));
      break;
  }

  var appDir = d.dir(appPath, [
    d.appPubspec({'lib': '1.0.0'}),
    d.dir('lib'),
    ...appDirContents,
  ]);
  var overridesDir = d.dir('overrides', overridesDirContents);

  await appDir.create();
  await overridesDir.create();

  var args = <String>[];

  // Setup command line arguments.
  switch (location) {
    case PubspecOverridesLocation.default_:
      break;
    case PubspecOverridesLocation.defaultDisabled:
      args.addAll(['--pubspec-overrides', 'none']);
      break;
    case PubspecOverridesLocation.customRelative:
      args.addAll(['--pubspec-overrides', p.join('..', 'overrides', 'a.yaml')]);
      break;
    case PubspecOverridesLocation.customAbsolute:
      args.addAll([
        '--pubspec-overrides',
        p.join(overridesDir.io.absolute.path, 'a.yaml')
      ]);
      break;
  }

  dynamic warning;
  switch (location) {
    case PubspecOverridesLocation.default_:
      warning =
          'Warning: pubspec.yaml has overrides from pubspec_overrides.yaml';
      break;
    case PubspecOverridesLocation.defaultDisabled:
      break;
    case PubspecOverridesLocation.customRelative:
    case PubspecOverridesLocation.customAbsolute:
      warning = 'Warning: pubspec.yaml has overrides from '
          '${p.join('..', 'overrides', 'a.yaml')}';
      break;
  }

  await pubCommand(command, args: args, warning: warning);

  Future<void> validatePackage({String libVersion}) => d.dir(appPath, [
        d.packageConfigFile([
          d.packageConfigEntry(
            name: 'lib',
            version: libVersion,
            languageVersion: '2.7',
          ),
          d.packageConfigEntry(
            name: 'myapp',
            path: '.',
            languageVersion: '0.1',
          ),
        ])
      ]).validate();

  switch (location) {
    case PubspecOverridesLocation.default_:
    case PubspecOverridesLocation.customRelative:
    case PubspecOverridesLocation.customAbsolute:
      // Validate that the overrides were applied.
      await validatePackage(libVersion: '2.0.0');
      break;
    case PubspecOverridesLocation.defaultDisabled:
      // Validate that the overrides were not applied.
      await validatePackage(libVersion: '1.0.0');
      break;
  }
}
