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
  @override
  String get name => 'repair';
  @override
  String get description => 'Reinstall cached packages.';
  @override
  String get invocation => 'pub cache repair';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-cache';
  @override
  bool get takesArguments => false;

  @override
  Future run() async {
    // Repair every cached source.
    final repairResults = (await Future.wait(
            cache.sources.all.map(cache.source).map((source) async {
      return source is CachedSource
          ? await source.repairCachedPackages()
          : <RepairResult>[];
    })))
        .expand((x) => x);

    final successes = [
      for (final result in repairResults)
        if (result.success) result.package
    ];
    final failures = [
      for (final result in repairResults)
        if (!result.success) result.package
    ];

    if (successes.isNotEmpty) {
      var packages = pluralize('package', successes.length);
      log.message('Reinstalled ${log.green(successes.length)} $packages.');
    }

    if (failures.isNotEmpty) {
      var packages = pluralize('package', failures.length);
      var buffer = StringBuffer(
          'Failed to reinstall ${log.red(failures.length)} $packages:\n');

      for (var id in failures) {
        buffer.write('- ${log.bold(id.name)} ${id.version}');
        if (id.source != cache.sources.defaultSource) {
          buffer.write(' from ${id.source}');
        }
        buffer.writeln();
      }

      log.message(buffer.toString());
    }

    var globalRepairResults = await globals.repairActivatedPackages();
    if (globalRepairResults.first.isNotEmpty) {
      var packages = pluralize('package', globalRepairResults.first.length);
      log.message(
          'Reactivated ${log.green(globalRepairResults.first.length)} $packages.');
    }

    if (globalRepairResults.last.isNotEmpty) {
      var packages = pluralize('package', globalRepairResults.last.length);
      log.message(
          'Failed to reactivate ${log.red(globalRepairResults.last.length)} $packages:\n' +
              globalRepairResults.last
                  .map((name) => '- ${log.bold(name)}')
                  .join('\n'));
    }

    if (successes.isEmpty && failures.isEmpty) {
      log.message('No packages in cache, so nothing to repair.');
    }

    if (failures.isNotEmpty || globalRepairResults.last.isNotEmpty) {
      await flushThenExit(exit_codes.UNAVAILABLE);
    }
  }
}
