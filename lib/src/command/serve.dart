// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'barback.dart';

/// Handles the `serve` pub command.
class ServeCommand extends BarbackCommand {
  @override
  String get name => 'serve';
  @override
  String get description => 'Deprecated command';
  @override
  bool get hidden => true;

  ServeCommand() {
    argParser.addOption('define', hide: true);
    argParser.addOption('hostname', hide: true);
    argParser.addOption('port', hide: true);
    argParser.addFlag('log-admin-url', hide: true);
    argParser.addOption('admin-port', hide: true);
    argParser.addOption('build-delay', hide: true);
    argParser.addFlag('dart2js', hide: true);
    argParser.addFlag('force-poll', hide: true);
  }
}
