// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../command_runner.dart';
import '../entrypoint.dart';
import '../log.dart' as log;
import '../utils.dart';

class CheckResolutionUpToDateCommand extends PubCommand {
  @override
  String get name => 'check-resolution-up-to-date';

  @override
  bool get hidden => true;

  @override
  String get description => '''
Do a fast timestamp-based check to see resolution is up-to-date and internally
consistent.

If timestamps are correctly ordered, exit 0, and do not check the external sources for
newer versions.
Otherwise exit non-zero.
''';

  @override
  String get argumentsDescription => '';

  CheckResolutionUpToDateCommand();

  @override
  Future<void> runProtected() async {
    final result = Entrypoint.isResolutionUpToDate(directory, cache);
    if (result == null) {
      fail('Resolution needs updating. Run `$topLevelProgram pub get`');
    } else {
      log.message('Resolution is up-to-date');
    }
  }
}
