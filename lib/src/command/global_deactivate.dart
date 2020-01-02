// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../log.dart' as log;
import '../utils.dart';

/// Handles the `global deactivate` pub command.
class GlobalDeactivateCommand extends PubCommand {
  @override
  String get name => 'deactivate';
  @override
  String get description => 'Remove a previously activated package.';
  @override
  String get invocation => 'pub global deactivate <package>';

  @override
  void run() {
    // Make sure there is a package.
    if (argResults.rest.isEmpty) {
      usageException('No package to deactivate given.');
    }

    // Don't allow extra arguments.
    if (argResults.rest.length > 1) {
      var unexpected = argResults.rest.skip(1).map((arg) => '"$arg"');
      var arguments = pluralize('argument', unexpected.length);
      usageException('Unexpected $arguments ${toSentence(unexpected)}.');
    }

    if (!globals.deactivate(argResults.rest.first)) {
      dataError('No active package ${log.bold(argResults.rest.first)}.');
    }
  }
}
