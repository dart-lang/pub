// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/yaml_edit/src/utils.dart';
import 'package:pub/src/yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

/// Interface for creating golden Test cases
class TestCases {
  final List<_TestCase> testCases;

  /// Creates a [TestCases] object based on test directory and golden directory
  /// path.
  static Future<TestCases> getTestCases(Uri testDirUri, Uri goldDirUri) async {
    final testDir = Directory.fromUri(testDirUri);

    if (!testDir.existsSync()) return TestCases([]);

    /// Recursively grab all the files in the testing directory.
    return TestCases(await testDir
        .list(recursive: true, followLinks: false)
        .where((entity) => entity.path.endsWith('.test'))
        .map((entity) => entity.uri)
        .map((inputUri) {
      final inputWithoutExtension =
          p.basenameWithoutExtension(inputUri.toFilePath());
      final goldenUri = goldDirUri.resolve('./$inputWithoutExtension.golden');

      return _TestCase(inputUri, goldenUri);
    }).toList());
  }

  /// Tests all the [_TestCase]s if the golden files exist, create the golden
  /// files otherwise.
  void test() {
    var tested = 0;
    var created = 0;

    for (final testCase in testCases) {
      testCase.testOrCreate();
      if (testCase.state == _TestCaseStates.testedGoldenFile) {
        tested++;
      } else if (testCase.state == _TestCaseStates.createdGoldenFile) {
        created++;
      }
    }

    print(
        'Successfully tested $tested inputs against golden files, created $created golden files');
  }

  TestCases(this.testCases);

  int get length => testCases.length;
}

/// Enum representing the different states of [_TestCase]s.
enum _TestCaseStates { initialized, createdGoldenFile, testedGoldenFile }

/// Interface for a golden test case. Handles the logic for test conduct/golden
/// test update accordingly.
class _TestCase {
  final Uri inputUri;
  final Uri goldenUri;
  final List<String> states = [];

  String info;
  YamlEditor yamlBuilder;
  List<_YamlModification> modifications;

  String inputLineEndings = '\n';

  _TestCaseStates state = _TestCaseStates.initialized;

  _TestCase(this.inputUri, this.goldenUri) {
    final inputFile = File.fromUri(inputUri);
    if (!inputFile.existsSync()) {
      throw Exception('Input File does not exist!');
    }

    _initialize(inputFile);
  }

  /// Initializes the [_TestCase] by reading the corresponding [inputFile] and
  /// parsing the different portions, and then running the input yaml against
  /// the specified modifications.
  ///
  /// Precondition: [inputFile] must exist, and inputs must be well-formatted.
  void _initialize(File inputFile) {
    final input = inputFile.readAsStringSync();

    final inputLineEndings = getLineEnding(input);
    final inputElements = input.split('---$inputLineEndings');

    if (inputElements.length != 3) {
      throw AssertionError('File ${inputFile.path} is not properly formatted.');
    }

    info = inputElements[0];
    yamlBuilder = YamlEditor(inputElements[1]);
    final rawModifications = _getValueFromYamlNode(loadYaml(inputElements[2]));
    modifications = _parseModifications(rawModifications);

    /// Adds the initial state as well, so we can check that the simplest
    /// parse -> immediately dump does not affect the string.
    states.add(yamlBuilder.toString());

    _performModifications();
  }

  void _performModifications() {
    for (final mod in modifications) {
      _performModification(mod);
      states.add(yamlBuilder.toString());
    }
  }

  void _performModification(_YamlModification mod) {
    switch (mod.method) {
      case YamlModificationMethod.update:
        yamlBuilder.update(mod.path, mod.value);
        return;
      case YamlModificationMethod.remove:
        yamlBuilder.remove(mod.path);
        return;
      case YamlModificationMethod.appendTo:
        yamlBuilder.appendToList(mod.path, mod.value);
        return;
      case YamlModificationMethod.prependTo:
        yamlBuilder.prependToList(mod.path, mod.value);
        return;
      case YamlModificationMethod.insert:
        yamlBuilder.insertIntoList(mod.path, mod.index, mod.value);
        return;
      case YamlModificationMethod.splice:
        yamlBuilder.spliceList(mod.path, mod.index, mod.deleteCount, mod.value);
        return;
    }
  }

  void testOrCreate() {
    final goldenFile = File.fromUri(goldenUri);
    if (!goldenFile.existsSync()) {
      createGoldenFile(goldenFile);
    } else {
      testGoldenFile(goldenFile);
    }
  }

  void createGoldenFile(File goldenFile) {
    /// Assumes user wants the golden file to have the same line endings as
    /// the input file.
    final goldenOutput = states.join('---$inputLineEndings');

    goldenFile.writeAsStringSync(goldenOutput);
    state = _TestCaseStates.createdGoldenFile;
  }

  /// Tests the golden file. Ensures that the number of states are the same, and
  /// that the individual states are the same.
  void testGoldenFile(File goldenFile) {
    final inputFileName = p.basename(inputUri.toFilePath());
    final golden = goldenFile.readAsStringSync();
    final goldenStates = golden.split('---${getLineEnding(golden)}');

    group('testing $inputFileName - input and golden files have', () {
      test('same number of states', () {
        expect(states.length, equals(goldenStates.length));
      });

      for (var i = 0; i < states.length; i++) {
        test('same state $i', () {
          expect(states[i], equals(goldenStates[i]));
        });
      }
    });

    state = _TestCaseStates.testedGoldenFile;
  }
}

/// Converts a [YamlList] into a Dart list.
List _getValueFromYamlList(YamlList node) {
  return node.value.map((n) {
    if (n is YamlNode) return _getValueFromYamlNode(n);
    return n;
  }).toList();
}

/// Converts a [YamlMap] into a Dart Map.
Map _getValueFromYamlMap(YamlMap node) {
  final keys = node.keys;
  final result = {};
  for (final key in keys) {
    result[key.value] = result[key].value;
  }

  return result;
}

/// Converts a [YamlNode] into a Dart object.
dynamic _getValueFromYamlNode(YamlNode node) {
  switch (node.runtimeType) {
    case YamlList:
      return _getValueFromYamlList(node);
    case YamlMap:
      return _getValueFromYamlMap(node);
    default:
      return node.value;
  }
}

/// Converts the list of modifications from the raw input to [_YamlModification]
/// objects.
List<_YamlModification> _parseModifications(List<dynamic> modifications) {
  return modifications.map((mod) {
    Object value;
    int index;
    int deleteCount;
    final method = _getModificationMethod(mod[0] as String);

    final path = mod[1] as List;

    if (method == YamlModificationMethod.appendTo ||
        method == YamlModificationMethod.update ||
        method == YamlModificationMethod.prependTo) {
      value = mod[2];
    } else if (method == YamlModificationMethod.insert) {
      index = mod[2];
      value = mod[3];
    } else if (method == YamlModificationMethod.splice) {
      index = mod[2];
      deleteCount = mod[3];

      if (mod[4] is! List) {
        throw ArgumentError('Invalid array ${mod[4]} used in splice');
      }

      value = mod[4];
    }

    return _YamlModification(method, path, index, value, deleteCount);
  }).toList();
}

/// Gets the YAML modification method corresponding to [method]
YamlModificationMethod _getModificationMethod(String method) {
  switch (method) {
    case 'update':
      return YamlModificationMethod.update;
    case 'remove':
      return YamlModificationMethod.remove;
    case 'append':
    case 'appendTo':
      return YamlModificationMethod.appendTo;
    case 'prepend':
    case 'prependTo':
      return YamlModificationMethod.prependTo;
    case 'insert':
    case 'insertIn':
      return YamlModificationMethod.insert;
    case 'splice':
      return YamlModificationMethod.splice;
    default:
      throw Exception('$method not recognized!');
  }
}

/// Class representing an abstract YAML modification to be performed
class _YamlModification {
  final YamlModificationMethod method;
  final List<dynamic> path;
  final int index;
  final dynamic value;
  final int deleteCount;

  _YamlModification(
      this.method, this.path, this.index, this.value, this.deleteCount);

  @override
  String toString() =>
      'method: $method, path: $path, index: $index, value: $value, deleteCount: $deleteCount';
}
