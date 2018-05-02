// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/command_runner.dart';

import '../log.dart' as log;
import '../utils.dart';

/// Shared base class for [BuildCommand] and [ServeCommand].
abstract class BarbackCommand extends Command {
  @override
  bool get takesArguments => false;

  @override
  usageException(_) => throw new UsageException(_deprecationError, '');

  String get _deprecationError =>
      log.red("Dart 2 has a new build system. Learn how to migrate "
          "from ${log.bold('pub build')} and\n"
          "${log.bold('pub serve')}: https://webdev.dartlang.org/dart-2\n");

  run() {
    // Switch to JSON output if specified. We need to do this before parsing
    // the source directories so an error will be correctly reported in JSON
    // format.
    log.json.enabled =
        argResults.options.contains("format") && argResults["format"] == "json";

    fail(_deprecationError);
  }
}
