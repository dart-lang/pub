// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:pub/src/yaml_edit.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

/// Interface for creating golden Test cases
class TestCases {
  final List<TestCase> testCases;

  /// Creates a [TestCases] object based on test directory and golden directory
  /// path.
  static Future<TestCases> getTestCases(
      String testDirPath, String goldDirPath) async {
    var testDir = Directory(testDirPath);
    var testCaseList = [];

    if (testDir.existsSync()) {
      /// Recursively grab all the files in the testing directory.
      var entityStream = testDir.list(recursive: true, followLinks: false);
      entityStream =
          entityStream.where((entity) => entity.path.endsWith('.test'));

      var testCasesPathStream = entityStream.map((entity) => entity.path);
      var testCasePaths = await testCasesPathStream.toList();

      testCaseList = testCasePaths.map((inputPath) {
        var inputName = inputPath.split('/').last;
        var inputNameWithoutExt = inputName.substring(0, inputName.length - 5);
        var goldenPath = '$goldDirPath/$inputNameWithoutExt.golden';

        return TestCase(inputPath, goldenPath);
      }).toList();
    }

    return TestCases(testCaseList);
  }

  /// Tests all the [TestCase]s if the golden files exist, create the golden
  /// files otherwise.
  void test() {
    var tested = 0;
    var created = 0;

    for (var testCase in testCases) {
      testCase.testOrCreate();
      if (testCase.state == TestCaseStates.testedGoldenFile) {
        tested++;
      } else if (testCase.state == TestCaseStates.createdGoldenFile) {
        created++;
      }
    }

    print(
        'Successfully tested $tested inputs against golden files, created $created golden files');
  }

  TestCases(this.testCases);

  int get length => testCases.length;
}

/// Enum representing the different states of [TestCase]s.
enum TestCaseStates { initialized, createdGoldenFile, testedGoldenFile }

/// Interface for a golden test case. Handles the logic for test conduct/golden
/// test update accordingly.
class TestCase {
  final String inputPath;
  final String goldenPath;
  final List<String> states = [];

  String info;
  YamlEditor yamlBuilder;
  List<YamlModification> modifications;

  TestCaseStates state = TestCaseStates.initialized;

  TestCase(this.inputPath, this.goldenPath) {
    var inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      throw Exception('Input File does not exist!');
    }

    initialize(inputFile);
  }

  /// Initializes the [TestCase] by reading the corresponding [inputFile] and parsing
  /// the different portions, and then running the input yaml against the specified
  /// modifications.
  ///
  /// Precondition: [inputFile] must exist.
  void initialize(File inputFile) {
    var input = inputFile.readAsStringSync();
    var inputElements = input.split('\n---\n');

    info = inputElements[0];
    yamlBuilder = YamlEditor(inputElements[1]);
    var rawModifications = getValueFromYamlNode(loadYaml(inputElements[2]));
    modifications = parseModifications(rawModifications);

    /// Adds the initial state as well, so we can check that the simplest
    /// parse -> immediately dump does not affect the string.
    states.add(yamlBuilder.toString());

    performModifications();
  }

  void performModifications() {
    for (var mod in modifications) {
      performModification(mod);
      states.add(yamlBuilder.toString());
    }
  }

  void performModification(YamlModification mod) {
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
    var goldenFile = File(goldenPath);
    if (!goldenFile.existsSync()) {
      createGoldenFile();
    } else {
      testGoldenFile(goldenFile);
    }
  }

  void createGoldenFile() {
    var goldenOutput = states.join('\n---\n');

    var goldenFile = File(goldenPath);
    goldenFile.writeAsStringSync(goldenOutput);
    state = TestCaseStates.createdGoldenFile;
  }

  /// Tests the golden file. Ensures that the number of states are the same, and
  /// that the individual states are the same.
  void testGoldenFile(File goldenFile) {
    var inputFileName = inputPath.split('/').last;
    var goldenStates = goldenFile.readAsStringSync().split('\n---\n');

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

    state = TestCaseStates.testedGoldenFile;
  }
}

/// Converts a [YamlList] into a Dart list.
List getValueFromYamlList(YamlList node) {
  return node.value.map((n) {
    if (n is YamlNode) return getValueFromYamlNode(n);
    return n;
  }).toList();
}

/// Converts a [YamlMap] into a Dart Map.
Map getValueFromYamlMap(YamlMap node) {
  var keys = node.keys;
  var result = {};
  for (var key in keys) {
    result[key.value] = result[key].value;
  }

  return result;
}

/// Converts a [YamlNode] into a Dart object.
dynamic getValueFromYamlNode(YamlNode node) {
  switch (node.runtimeType) {
    case YamlList:
      return getValueFromYamlList(node);
    case YamlMap:
      return getValueFromYamlMap(node);
    default:
      return node.value;
  }
}

/// Converts the list of modifications from the raw input to [YamlModification] objects.
List<YamlModification> parseModifications(List<dynamic> modifications) {
  return modifications.map((mod) {
    Object value;
    int index;
    int deleteCount;
    final method = getModificationMethod(mod[0] as String);

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

    return YamlModification(method, path, index, value, deleteCount);
  }).toList();
}

/// Gets the YAML modification method corresponding to [method]
YamlModificationMethod getModificationMethod(String method) {
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
class YamlModification {
  final YamlModificationMethod method;
  final List<dynamic> path;
  final int index;
  final dynamic value;
  final int deleteCount;

  YamlModification(
      this.method, this.path, this.index, this.value, this.deleteCount);

  @override
  String toString() =>
      'method: $method, path: $path, index: $index, value: $value, deleteCount: $deleteCount';
}
