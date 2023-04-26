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
///   [pub]
///   [pub, get]
///   ...
/// ]
/// ```
Iterable<List<String>> _extractCommands(
  List<String> parents,
  Iterable<Command> cmds,
) sync* {
  if (parents.isNotEmpty) {
    yield parents;
  }
  // Track that we don't add more than once, we don't want to test aliases
  final names = <String>{};
  yield* cmds
      .where((sub) => !sub.hidden && names.add(sub.name))
      .map(
        (sub) => _extractCommands(
          [...parents, sub.name],
          sub.subcommands.values,
        ),
      )
      .expand((cmds) => cmds);
}

/// Tests for `pub ... --help`.
Future<void> main() async {
  final cmds = _extractCommands([], PubCommandRunner().commands.values);
  for (final c in cmds) {
    testWithGolden('pub ${c.join(' ')} --help', (ctx) async {
      await ctx.run(
        [...c, '--help'],
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
