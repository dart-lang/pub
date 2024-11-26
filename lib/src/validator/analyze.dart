// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../io.dart';

import '../log.dart';
import '../validator.dart';

/// Runs `dart analyze` and gives a warning if it returns non-zero.
class AnalyzeValidator extends Validator {
  // Only analyze dart code in the following sub-folders and files.
  static const List<String> _entriesToAnalyze = [
    'bin',
    'lib',
    'build.dart',
    'link.dart',
  ];

  @override
  Future<void> validate() async {
    final entries = _entriesToAnalyze
        .map((dir) => p.join(package.dir, dir))
        .where(entryExists);
    final result = await runProcess(
      Platform.resolvedExecutable,
      ['analyze', ...entries, p.join(package.dir, 'pubspec.yaml')],
    );
    if (result.exitCode != 0) {
      final limitedOutput = limitLength(result.stdout, 1000);
      warnings
          .add('`dart analyze` found the following issue(s):\n$limitedOutput');
    }
  }
}
