// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../io.dart';
import '../log.dart' as log;

class CacheCleanCommand extends PubCommand {
  @override
  String get name => 'clean';
  @override
  String get description => 'Clears the entire system cache.';
  @override
  bool get takesArguments => false;

  @override
  Future<void> runProtected() async {
    if (entryExists(cache.rootDir)) {
      log.message('Removing pub cache directory ${cache.rootDir}.');
      deleteEntry(cache.rootDir);
    } else {
      log.message('No pub cache at ${cache.rootDir}.');
    }
  }
}
