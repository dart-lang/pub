// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../command_runner.dart';
import '../io.dart';
import '../log.dart' as log;
import '../utils.dart';

class CacheCleanCommand extends PubCommand {
  @override
  String get name => 'clean';
  @override
  String get description => 'Clears the global PUB_CACHE.';
  @override
  bool get takesArguments => false;

  CacheCleanCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Don\'t ask for confirmation.',
      negatable: false,
    );
  }

  @override
  Future<void> runProtected() async {
    if (dirExists(cache.rootDir)) {
      if (asBool(argResults['force']) || await confirm('''
This will remove everything inside ${cache.rootDir}.
You will have to run `$topLevelProgram pub get` again in each project.
Are you sure?''')) {
        log.message('Removing pub cache directory ${cache.rootDir}.');
        cache.clean();
      }
    } else {
      log.message('No pub cache at ${cache.rootDir}.');
    }
  }
}
