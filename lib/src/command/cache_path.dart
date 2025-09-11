// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../log.dart' as log;

class CachePathCommand extends PubCommand {
  @override
  String get name => 'path';
  @override
  String get description => 'Prints the path to the global PUB_CACHE.';
  @override
  bool get takesArguments => false;

  CachePathCommand();

  @override
  Future<void> runProtected() async {
    log.message(cache.rootDir);
  }
}
