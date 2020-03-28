// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:test/test.dart';
import 'package:pub/src/config_helper.dart';

<<<<<<< HEAD
=======
import '../validator/language_version_test.dart';

>>>>>>> Add new command pub config
void main() {
  const allowedOptions = [
    'verbosity',
    'test-value',
    'nested.something.test-value'
  ];
  const standardConfig = '''verbosity: "normal"''';
  var args = [allowedOptions, standardConfig];
<<<<<<< HEAD
  ConfigHelper conf;
=======
  var conf = null;
>>>>>>> Add new command pub config

  group('Value insertion', () {
    setUp(() {
      conf = ConfigHelper.simpleTest(args);
    });

    test('Existing top level config option (String) can be inserted', () {
      conf.set('verbosity', 'hi');
      var receivedVal = conf.get('verbosity');
      expect(receivedVal, equals('hi'));
    });

    test('Array can be inserted into top level field', () {
<<<<<<< HEAD
      conf.set('test-value', [1, 'a', true, 3.14]);
      expect(conf.get('test-value'), equals([1, 'a', true, 3.14]));
    });

    test('Array can be inserted into nested field', () {
      conf.set('nested.something.test-value', [1, 'a', true, 3.14]);
      expect(conf.get('nested.something.test-value'),
          equals([1, 'a', true, 3.14]));
    });

    test('A single value in an array can be changed (top level)', () {
      conf.set('test-value', [1, 'a', true, 3.14]);
=======
      conf.set('test-value', [1, "a", true, 3.14]);
      expect(conf.get('test-value'), equals([1, "a", true, 3.14]));
    });

    test('Array can be inserted into nested field', () {
      conf.set('nested.something.test-value', [1, "a", true, 3.14]);
      expect(conf.get('nested.something.test-value'),
          equals([1, "a", true, 3.14]));
    });

    test('A single value in an array can be changed (top level)', () {
      conf.set('test-value', [1, "a", true, 3.14]);
>>>>>>> Add new command pub config
      conf.set('test-value', 3, index: 0);
      expect(conf.get('test-value')[0], equals(3));
    });

    test('A single value in an array can be changed (nested)', () {
<<<<<<< HEAD
      conf.set('nested.something.test-value', [1, 'a', true, 3.14]);
=======
      conf.set('nested.something.test-value', [1, "a", true, 3.14]);
>>>>>>> Add new command pub config
      conf.set('nested.something.test-value', false, index: 2);
      expect(conf.get('nested.something.test-value')[2], equals(false));
    });

    test('Strings with spaces can be inserted', () {
      conf.set('verbosity', 'word1 word2 word3');
      expect(conf.get('verbosity'), equals('word1 word2 word3'));
    });

    test('Existing top level config option (int) can be inserted', () {
      conf.set('verbosity', 50);
      var receivedVal = conf.get('verbosity');
      expect(receivedVal, equals(50));
    });

    test('Existing top level config option (double) can be inserted', () {
      conf.set('verbosity', 3.14159);
      var receivedVal = conf.get('verbosity');
      expect(receivedVal, equals(3.14159));
    });

    test('Existing top level config option (bool) can be inserted', () {
      conf.set('verbosity', true);
      var receivedVal = conf.get('verbosity');
      expect(receivedVal, equals(true));
    });

    test('New top level config option (String) can be inserted', () {
      conf.set('test-value', 'hi');
      var receivedVal = conf.get('test-value');
      expect(receivedVal, equals('hi'));
    });

    test('New top level config option (int) can be inserted', () {
      conf.set('test-value', 50);
      var receivedVal = conf.get('test-value');
      expect(receivedVal, equals(50));
    });

    test('New top level config option (double) can be inserted', () {
      conf.set('test-value', 3.14159);
      var receivedVal = conf.get('test-value');
      expect(receivedVal, equals(3.14159));
    });

    test('New top level config option (bool) can be inserted', () {
      conf.set('test-value', true);
      var receivedVal = conf.get('test-value');
      expect(receivedVal, equals(true));
    });

    test('Nested config option can be inserted', () {
      conf.set('nested.something.test-value', 'sample-text');
      expect(conf.get('nested.something.test-value'), equals('sample-text'));
    });
  });

  group('File handling', () {
    test('Empty config file is being handled', () {
<<<<<<< HEAD
      var conf = ConfigHelper.simpleTest(args, basename: 'temp_config.yaml');
=======
      var conf = ConfigHelper.simpleTest(args, 'temp_config.yaml');
>>>>>>> Add new command pub config

      if (conf.exists) conf.delete();
      conf.createEmptyConfigFile();
      conf.set('test-value', 'smthin');
      var receivedValue = conf.get('test-value');
      conf.delete();
      expect(receivedValue, equals('smthin'));
    });

    test('Custom missing config file is being handled (multiple times)', () {
<<<<<<< HEAD
      for (var i = 0; i < 3; i++) {
        var conf = ConfigHelper.simpleTest(args, basename: 'temp_config.yaml');
=======
      for (int i = 0; i < 3; i++) {
        var conf = ConfigHelper.simpleTest(args, 'temp_config.yaml');
>>>>>>> Add new command pub config
        if (conf.exists) conf.delete();
        conf.set('test-value', 'smthin else');
        var receivedValue = conf.get('test-value');
        conf.delete();
        expect(receivedValue, equals('smthin else'));
      }
    });

    test('The updated config is written to an existing file', () {
      fileTest(args, 'pub_config.yaml');
    });

    test('The updated config is written to a new file', () {
      conf = fileTest(args, 'temp.yaml');
      conf.delete();
    });
  });
}

ConfigHelper fileTest(var args, String filename) {
<<<<<<< HEAD
  var conf = ConfigHelper.simpleTest(args, basename: filename);
=======
  var conf = ConfigHelper.simpleTest(args, filename);
>>>>>>> Add new command pub config
  final previousValue = conf.get('verbosity');
  final allowedValues = [
    'none',
    'error',
    'warning',
    'normal',
    'io',
    'solver',
    'all'
  ];
<<<<<<< HEAD
  final tempVal = allowedValues[
=======
  String tempVal = allowedValues[
>>>>>>> Add new command pub config
      (allowedValues.indexOf(previousValue) + 1) % allowedValues.length];
  conf.set('verbosity', tempVal);
  conf.write();
  var file = File(conf.location);
<<<<<<< HEAD
  final content = file.readAsStringSync();
  conf.set('verbosity', previousValue);
  conf.write();
  expect(content, contains('verbosity: "$tempVal"'));
=======
  String content = file.readAsStringSync();
  conf.set('verbosity', previousValue);
  conf.write();
  expect(content, contains('verbosity: "${tempVal}"'));
>>>>>>> Add new command pub config
  expect(conf.get('verbosity'), equals(previousValue));
  return conf;
}
