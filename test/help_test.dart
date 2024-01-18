// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:pub/src/command_runner.dart' show PubCommandRunner;

import 'golden_file.dart';

/// Extract all commands and subcommands.
///
/// Result will be an iterable of lists, illustrated as follows:
/// ```
/// [
///   [pub, --help]
///   [pub, get, --help]
///   ...
/// ]
/// ```
Iterable<List<String>> _extractCommands() sync* {
  // dedup aliases.
  Set visitedCommands = <Command>{};
  final stack = [PubCommandRunner().commands.values.toList()];
  final parents = <String>[];
  while (true) {
    final commands = stack.last;
    if (commands.isEmpty) {
      stack.removeLast();
      yield ['pub', ...parents, '--help'];
      if (parents.isEmpty) break;
      parents.removeLast();
    } else {
      final command = commands.removeLast();
      if (!visitedCommands.add(command)) continue;
      if (command.hidden) continue;
      stack.add(command.subcommands.values.toList());
      parents.add(command.name);
    }
  }
}

/// Tests for `pub ... --help`.
Future<void> main() async {
  final cmds = _extractCommands();
  for (final c in cmds) {
    testWithGolden(c.join(' '), (ctx) async {
      await ctx.run(
        c.skip(1).toList(),
        environment: {
          // Use more columns to avoid unintended line breaking.
          '_PUB_TEST_TERMINAL_COLUMNS': '200',
          'HOME': null,
          'PUB_CACHE': null,
        },
      );
    });
  }
}
