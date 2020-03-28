// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

<<<<<<< HEAD
import 'package:test/test.dart';
import '../test_pub.dart';

void main() {
  RunCommand basicCommand;
  /*const allowedOptions = [
    'verbosity',
    'test-value',
    'nested.something.test-value'
  ];*/
  const standardConfig = '''verbosity: "normal"''';
  //var args = [allowedOptions, standardConfig];
  basicCommand = RunCommand('config', RegExp(''));
  //ConfigHelper conf;

  test('pub config help page shows all available flags/options', () async {
    const expectedOutput = '''Change configuration for pub.
=======
import 'dart:io';
import 'package:test/test.dart';
import '../test_pub.dart';
import 'package:pub/src/config_helper.dart';

void main() {
  var basicCommand = null;
  const allowedOptions = [
    'verbosity',
    'test-value',
    'nested.something.test-value'
  ];
  const standardConfig = '''verbosity: "normal"''';
  var args = [allowedOptions, standardConfig];
  basicCommand = RunCommand('config', RegExp(''));
  String oldContent = null;
  var conf = null;
  var file = null;

  test('pub config help page shows all available flags/options', () async {
    String expectedOutput = '''Change configuration for pub.
>>>>>>> Add new command pub config

Usage: pub config [options]
-h, --help          Print this usage information.
-v, --verbosity     Default verbosity level
                    [none, error, warning, normal, io, solver, all]
-s, --show          Show current config
    --is-verbose    Print a message if output is verbose

Run "pub help" to see global options.''';
    await pubCommand(basicCommand, output: expectedOutput);
    await pubCommand(basicCommand, args: ['--help'], output: expectedOutput);
  });

  group('Messing with the config file..', () {
<<<<<<< HEAD
    test('An error message is created if the configuration file is invalid',
        () async {
      await pubCommand(basicCommand,
          args: ['--make-invalid', '--show'],
          error: RegExp(r'^Could not parse configuration file:'));
    });

    test('Default config is being displayed correctly', () async {
      await pubCommand(basicCommand,
          args: ['--make-empty', '--show'],
          output: 'Current config:\n' + standardConfig.replaceAll('"', ''));
    });

    test('Notifies about inserted value and displays it correctly', () async {
      var previousVerbosity = await getCurrentValue('verbosity');

      await pubCommand(basicCommand,
          args: ['--verbosity', 'all'],
          output: RegExp(r'verbosity set to all'));

      await pubCommand(basicCommand,
          args: ['--show'], output: contains('verbosity: all'));

      await pubCommand(basicCommand,
          args: ['--show', 'verbosity'], output: 'verbosity: all');

      await pubCommand(basicCommand, args: ['--verbosity', previousVerbosity]);
    });

    group('verbosity', () {
      String previousVal;

      setUpAll(() async {
        previousVal = await getCurrentValue('verbosity');
      });

      tearDownAll(() async {
        await pubCommand(basicCommand, args: ['--verbosity', previousVal]);
      });

      setUp(() async {
        await pubCommand(basicCommand, args: ['--verbosity', 'none']);
=======
    setUp(() {
      conf = ConfigHelper.simpleTest(args);
      file = new File(conf.location);
    });

    test('An error message is created if the configuration file is invalid',
        () async {
      oldContent = file.readAsStringSync();
      file.writeAsStringSync('\ninvalid yaml content', mode: FileMode.append);
      await pubCommand(basicCommand,
          args: ['--show'],
          error: RegExp(r'^Could not parse configuration file:'));
      file.writeAsStringSync(oldContent);
    });

    test('Default config is being displayed correctly', () async {
      file.writeAsStringSync('');
      await pubCommand(basicCommand,
          args: ['--show'],
          output: 'Current config:\n' + standardConfig.replaceAll('"', ''));
      file.writeAsStringSync(oldContent);
    });

    test('Notifies about inserted values and displays them correctly',
        () async {
      await pubCommand(basicCommand,
          args: ['--verbosity', 'all'],
          output: RegExp(r'verbosity set to all'));
      await pubCommand(basicCommand,
          args: ['--show'],
          output: 'Current config:\n' +
              standardConfig
                  .replaceAll('"', '')
                  .replaceAll('verbosity: normal', 'verbosity: all'));
      file.writeAsStringSync(oldContent);
    });

    group('verbosity', () {
      setUp(() {
        conf.set('verbosity', 'normal');
        conf.write();
      });

      tearDown(() {
        file.writeAsStringSync(oldContent);
>>>>>>> Add new command pub config
      });

      test('verbosity option overrides config', () async {
        await pubCommand(basicCommand,
            args: ['--is-verbose'],
            output: 'pub currently has verbose output',
            verbosity: 'all');
      });

      test('verbose flag overrides config', () async {
<<<<<<< HEAD
        await pubCommand(basicCommand,
            args: ['--is-verbose'], output: 'pub currently has verbose output');
=======
        await pubCommand(basicCommand, args: ['--is-verbose'],
            output: 'pub currently has verbose output');
>>>>>>> Add new command pub config
      });
    });
  });
}
<<<<<<< HEAD

Future<String> getCurrentValue(String val) async {
  var pub = await startPub(args: ['config', '--show', val]);
  var output =
      await pub.stdoutStream().toList(); //see ../test_pub.dart line 252
  for (var i = 0; i < output.length; i++) {
    if (output[i].contains(val)) {
      return output[i].substring(11);
    }
  }
  return null;
}
=======
>>>>>>> Add new command pub config
