import 'dart:io';
import 'dart:isolate';

import 'package:pub/src/exceptions.dart';

import './test_case.dart';

/// This script performs snapshot testing of the inputs in the testing directory
/// against golden files if they exist, and creates the golden files otherwise.
///
/// Input directory should be in `test/test_cases`, while the golden files should
/// be in `test/test_cases_golden`.
///
/// For more information on the expected input and output, refer to the README
/// in the testdata folder
Future<void> main() async {
  final packageUri =
      await Isolate.resolvePackageUri(Uri.parse('package:pub/yaml_edit.dart'));
  final testdataPath =
      packageUri.resolve('../test/yaml_edit/testdata').toFilePath();
  final inputDirectory = Directory('$testdataPath/input');
  final goldDirectory = Directory('$testdataPath/output');

  if (!inputDirectory.existsSync()) {
    throw FileException(
        'Testing Directory does not exist!', inputDirectory.path);
  }

  final testCases =
      await TestCases.getTestCases(inputDirectory.path, goldDirectory.path);

  testCases.test();
}
