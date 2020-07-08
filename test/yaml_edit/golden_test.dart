// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

  final testdataUri = packageUri.resolve('../test/yaml_edit/testdata/');
  final inputDirectory = Directory.fromUri(testdataUri.resolve('input/'));
  final goldDirectoryUri = testdataUri.resolve('output/');

  if (!inputDirectory.existsSync()) {
    throw FileException(
        'Testing Directory does not exist!', inputDirectory.path);
  }

  final testCases =
      await TestCases.getTestCases(inputDirectory.uri, goldDirectoryUri);

  testCases.test();
}
