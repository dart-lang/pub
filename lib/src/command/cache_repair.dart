// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../exit_codes.dart' as exit_codes;
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
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-cache';
  @override
  bool get takesArguments => false;

  @override
  Future<void> runProtected() async {
    // Delete any eventual temp-files left in the cache.
    cache.deleteTempDir();
    // Repair every cached source.
    final repairResults = (await Future.wait(
      <CachedSource>[cache.hosted, cache.git].map(
        (source) => source.repairCachedPackages(cache),
      ),
    ))
        .expand((x) => x);

    final successes = repairResults.where((result) => result.success);
    final failures = repairResults.where((result) => !result.success);

    if (successes.isNotEmpty) {
      var packages = pluralize('package', successes.length);
      log.message('Reinstalled ${log.green(successes.length)} $packages.');
    }

    if (failures.isNotEmpty) {
      var packages = pluralize('package', failures.length);
      var buffer = StringBuffer(
        'Failed to reinstall ${log.red(failures.length)} $packages:\n',
      );

      for (var failure in failures) {
        buffer.write('- ${log.bold(failure.packageName)} ${failure.version}');
        if (failure.source != cache.defaultSource) {
          buffer.write(' from ${failure.source}');
        }
        buffer.writeln();
      }

      log.message(buffer.toString());
    }

    var globalRepairResults = await globals.repairActivatedPackages();
    if (globalRepairResults.first.isNotEmpty) {
      var packages = pluralize('package', globalRepairResults.first.length);
      log.message(
        'Reactivated ${log.green(globalRepairResults.first.length)} $packages.',
      );
    }

    if (globalRepairResults.last.isNotEmpty) {
      var packages = pluralize('package', globalRepairResults.last.length);
      log.message(
        'Failed to reactivate ${log.red(globalRepairResults.last.length)} $packages:',
      );
      log.message(
        globalRepairResults.last
            .map((name) => '- ${log.bold(name)}')
            .join('\n'),
      );
    }

    if (successes.isEmpty && failures.isEmpty) {
      log.message('No packages in cache, so nothing to repair.');
    }

    if (failures.isNotEmpty || globalRepairResults.last.isNotEmpty) {
      overrideExitCode(exit_codes.UNAVAILABLE);
    }
  }
}
