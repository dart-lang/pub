// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../command.dart';
import '../log.dart' as log;
import '../package_name.dart';
import '../utils.dart';

/// Handles the `cache add` pub command.
class CacheAddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description => 'Install a package.';
  @override
  String get argumentsDescription =>
      '<package> [--version <constraint>] [--all]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-cache';

  CacheAddCommand() {
    argParser.addFlag(
      'all',
      help: 'Install all matching versions.',
      negatable: false,
    );

    argParser.addOption('version', abbr: 'v', help: 'Version constraint.');
  }

  @override
  Future<void> runProtected() async {
    // Make sure there is a package.
    if (argResults.rest.isEmpty) {
      usageException('No package to add given.');
    }

    // Don't allow extra arguments.
    if (argResults.rest.length > 1) {
      final unexpected = argResults.rest.skip(1).map((arg) => '"$arg"');
      final arguments = pluralize('argument', unexpected.length);
      usageException('Unexpected $arguments ${toSentence(unexpected)}.');
    }

    final package = argResults.rest.single;

    // Parse the version constraint, if there is one.
    var constraint = VersionConstraint.any;
    final versionArg = argResults.option('version');
    if (versionArg != null) {
      try {
        constraint = VersionConstraint.parse(versionArg);
      } on FormatException catch (error) {
        usageException(error.message);
      }
    }

    // TODO(rnystrom): Support installing from git too.
    final source = cache.hosted;

    // TODO(rnystrom): Allow specifying the server.
    final ids = (await cache.getVersions(source.refFor(package)))
        .where((id) => constraint.allows(id.version))
        .toList();

    if (ids.isEmpty) {
      // TODO(rnystrom): Show most recent unmatching version?
      fail('Package $package has no versions that match $constraint.');
    }

    Future<void> downloadVersion(PackageId id) async {
      final result = await cache.downloadPackage(id);
      if (!result.didUpdate) {
        log.message('Already cached ${id.name} ${id.version}.');
      }
    }

    if (argResults.flag('all')) {
      // Install them in ascending order.
      ids.sort((id1, id2) => id1.version.compareTo(id2.version));
      await Future.forEach(ids, downloadVersion);
    } else {
      // Pick the best matching version.
      ids.sort((id1, id2) => Version.prioritize(id1.version, id2.version));
      await downloadVersion(ids.last);
    }
  }
}
