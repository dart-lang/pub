// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/log.dart' as log;
import 'package:pub/src/pub_embeddable_command.dart';

class Runner extends CommandRunner<int> {
  ArgResults _options;

  Runner() : super('pub_command_runner', 'Tests the embeddable pub command.') {
    addCommand(PubEmbeddableCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      _options = super.parse(args);

      return await runCommand(_options);
    } on UsageException catch (error) {
      log.exception(error);
      return exit_codes.USAGE;
    }
  }

  @override
  Future<int> runCommand(ArgResults topLevelResults) async {
    return await super.runCommand(topLevelResults) ?? 0;
  }
}

Future<void> main(List<String> arguments) async {
  exitCode = await Runner().run(arguments);
}
