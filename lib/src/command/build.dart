// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'barback.dart';

/// Handles the `build` pub command.
class BuildCommand extends BarbackCommand {
  @override
  String get name => 'build';
  @override
  String get description => 'Deprecated command';
  @override
  bool get hidden => true;

  BuildCommand() {
    argParser.addOption('define', hide: true);
    argParser.addOption('format', hide: true);
    argParser.addOption('output', hide: true);
  }
}
