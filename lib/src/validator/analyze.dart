// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../io.dart';

import '../validator.dart';

/// Runs `dart analyze` and gives a warning if it returns non-zero.
class AnalyzeValidator extends Validator {
  @override
  Future<void> validate() async {
    final result = await runProcess(Platform.resolvedExecutable, [
      'analyze',
      '--fatal-infos',
      if (!p.equals(entrypoint.root.dir, p.current)) entrypoint.root.dir,
    ]);
    if (result.exitCode != 0) {
      warnings.add(
          '`dart analyze` found the following issue(s):\n${result.stdout.join('\n')}');
    }
  }
}
