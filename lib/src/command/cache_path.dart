// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';

/// Handles the `cache path` pub command.
class CachePathCommand extends PubCommand {
  String get name => "path";
  String get description => "Prints the location of the pub cache";
  String get invocation => "pub cache path";
  bool get hidden => true;
  bool get takesArguments => false;

  void run() {
    print(cache.rootDir);
  }
}
