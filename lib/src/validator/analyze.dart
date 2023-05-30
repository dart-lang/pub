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
  /// Only analyze dart code in the following sub-folders.
  @override
  Future<void> validate() async {
    final dirsToAnalyze = ['lib', 'test', 'bin']
        .map((dir) => p.join(entrypoint.rootDir, dir))
        .where(dirExists);
    final result = await runProcess(
      Platform.resolvedExecutable,
      ['analyze', ...dirsToAnalyze, p.join(entrypoint.rootDir, 'pubspec.yaml')],
    );
    if (result.exitCode != 0) {
      final limitedOutput = limitLength(result.stdout.join('\n'), 1000);
      warnings
          .add('`dart analyze` found the following issue(s):\n$limitedOutput');
    }
  }
}
