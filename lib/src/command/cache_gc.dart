// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../command.dart';
import '../command_runner.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package_config.dart';
import '../utils.dart';

class CacheGcCommand extends PubCommand {
  @override
  String get name => 'gc';
  @override
  String get description => 'Prunes unused packages from the system cache.';
  @override
  bool get takesArguments => false;

  final dontRemoveFilesOlderThan = const Duration(hours: 2);

  CacheGcCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Prune cache without confirmation',
      hideNegatedUsage: true,
    );
    argParser.addFlag(
      'ignore-timestamp',
      help: 'Also delete recent files',
      hideNegatedUsage: true,
    );
  }

  @override
  Future<void> runProtected() async {
    final activeRoots = cache.activeRoots();
    final validActiveRoots = <String>[];
    final paths = <String>{};
    for (final packageConfigPath in activeRoots) {
      late final PackageConfig packageConfig;
      try {
        packageConfig = PackageConfig.fromJson(
          json.decode(readTextFile(packageConfigPath)),
        );
      } on IOException catch (e) {
        // Failed to read file - probably got deleted.
        log.fine('Failed to read packageConfig $packageConfigPath: $e');
        continue;
      } on FormatException catch (e) {
        log.warning(
          'Failed to decode packageConfig $packageConfigPath: $e.\n'
          'It could be corrupted',
        );
        // Failed to decode - probably corrupted.
        continue;
      }
      for (final package in packageConfig.packages) {
        final rootUri = p.canonicalize(
          package.resolvedRootDir(packageConfigPath),
        );
        if (p.isWithin(cache.rootDir, rootUri)) {
          paths.add(rootUri);
        }
      }
      validActiveRoots.add(packageConfigPath);
    }
    final now = DateTime.now();
    final allPathsToGC =
        [
          for (final source in cache.cachedSources)
            ...await source.entriesToGc(
              cache,
              paths
                  .where(
                    (path) => p.isWithin(
                      p.canonicalize(cache.rootDirForSource(source)),
                      path,
                    ),
                  )
                  .toSet(),
            ),
        ].where((path) {
          // Only clear cache entries older than 2 hours to avoid race
          // conditions with ongoing `pub get` processes.
          final s = statPath(path);
          if (s.type == FileSystemEntityType.notFound) return false;
          if (argResults.flag('ignore-timestamp')) return true;
          return now.difference(s.modified) > dontRemoveFilesOlderThan;
        }).toList();
    if (validActiveRoots.isEmpty) {
      log.message('Found no active projects.');
    } else {
      final s = validActiveRoots.length == 1 ? '' : 's';
      log.message('Found ${validActiveRoots.length} active project$s:');
      for (final packageConfigPath in validActiveRoots) {
        final parts = p.split(packageConfigPath);
        var projectDir = packageConfigPath;
        if (parts[parts.length - 2] == '.dart_tool' &&
            parts[parts.length - 1] == 'package_config.json') {
          projectDir = p.joinAll(parts.sublist(0, parts.length - 2));
        }
        log.message('* $projectDir');
      }
    }
    var sum = 0;
    for (final entry in allPathsToGC) {
      if (dirExists(entry)) {
        for (final file in listDir(
          entry,
          recursive: true,
          includeHidden: true,
          includeDirs: false,
        )) {
          sum += tryStatFile(file)?.size ?? 0;
        }
      } else {
        sum += tryStatFile(entry)?.size ?? 0;
      }
    }
    if (sum == 0) {
      log.message('No unused cache entries found.');
      return;
    }
    log.message('');
    log.message(
      '''
All other projects will need to run `$topLevelProgram pub get` again to work correctly.''',
    );
    log.message('Will recover ${readableFileSize(sum)}.');

    if (argResults.flag('force') ||
        await confirm('Are you sure you want to continue?')) {
      await log.progress('Deleting unused cache entries', () async {
        for (final path in allPathsToGC..sort()) {
          tryDeleteEntry(path);
        }
      });
    }
  }
}
