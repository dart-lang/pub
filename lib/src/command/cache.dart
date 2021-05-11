// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import '../command.dart';
import 'cache_add.dart';
import 'cache_clean.dart';
import 'cache_list.dart';
import 'cache_repair.dart';

/// Handles the `cache` pub command.
class CacheCommand extends PubCommand {
  @override
  String get name => 'cache';
  @override
  String get description => 'Work with the system cache.';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-cache';

  CacheCommand() {
    addSubcommand(CacheAddCommand());
    addSubcommand(CacheListCommand());
    addSubcommand(CacheCleanCommand());
    addSubcommand(CacheRepairCommand());
  }
}
