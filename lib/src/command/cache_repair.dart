// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../exit_codes.dart' as exit_codes;
import '../io.dart';
import '../log.dart' as log;
import '../source/cached.dart';
import '../utils.dart';

/// Handles the `cache repair` pub command.
class CacheRepairCommand extends PubCommand {
  String get name => "repair";
  String get description => "Reinstall cached packages.";
  String get invocation => "pub cache repair";
  String get docUrl => "http://dartlang.org/tools/pub/cmd/pub-cache.html";
  bool get takesArguments => false;

  Future run() async {
    var successes = [];
    var failures = [];

    // Repair every cached source.
    for (var source in cache.sources) {
      if (source is! CachedSource) continue;

      var results = await source.repairCachedPackages();
      successes.addAll(results.first);
      failures.addAll(results.last);
    }

    if (successes.length > 0) {
      var packages = pluralize("package", successes.length);
      log.message("Reinstalled ${log.green(successes.length)} $packages.");
    }

    if (failures.length > 0) {
      var packages = pluralize("package", failures.length);
      var buffer = new StringBuffer(
          "Failed to reinstall ${log.red(failures.length)} $packages:\n");

      for (var id in failures) {
        buffer.write("- ${log.bold(id.name)} ${id.version}");
        if (cache.sources[id.source] != cache.sources.defaultSource) {
          buffer.write(" from ${id.source}");
        }
        buffer.writeln();
      }

      log.message(buffer.toString());
    }

    var results = await globals.repairActivatedPackages();
    if (results.first.length > 0) {
      var packages = pluralize("package", results.first.length);
      log.message("Reactivated ${log.green(results.first.length)} $packages.");
    }

    if (results.last.length > 0) {
      var packages = pluralize("package", results.last.length);
      log.message(
          "Failed to reactivate ${log.red(results.last.length)} $packages:\n" +
          results.last.map((name) => "- ${log.bold(name)}").join("\n"));
    }

    if (successes.length == 0 && failures.length == 0) {
      log.message("No packages in cache, so nothing to repair.");
    }

    if (failures.length > 0 || results.last.length > 0) {
      await flushThenExit(exit_codes.UNAVAILABLE);
    }
  }
}
