// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import 'global_activate.dart';
import 'global_deactivate.dart';
import 'global_list.dart';
import 'global_run.dart';

/// Handles the `global` pub command.
class GlobalCommand extends PubCommand {
  @override
  String get name => 'global';
  @override
  String get description => 'Work with global packages.';
  @override
  String get invocation => 'pub global <subcommand>';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-global';

  GlobalCommand() {
    addSubcommand(GlobalActivateCommand());
    addSubcommand(GlobalDeactivateCommand());
    addSubcommand(GlobalListCommand());
    addSubcommand(GlobalRunCommand());
  }
}
