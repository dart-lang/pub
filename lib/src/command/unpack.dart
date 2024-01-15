// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package_name.dart';
import '../solver/type.dart';
import '../source/hosted.dart';
import '../utils.dart';

/// Handles the `deps` pub command.
class UnpackCommand extends PubCommand {
  @override
  String get name => 'unpack';

  @override
  String get description => 'Downloads a package and unpacks it in place.\n'
      'Will resolve dependencies in the folder unless `--no-resolve` is passed.';

  @override
  String get argumentsDescription => 'package-name[:version]';

  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-unpack';

  @override
  bool get takesArguments => true;

  UnpackCommand() {
    argParser.addFlag(
      'resolve',
      help: 'Whether to do pub get in the downloaded folder',
      defaultsTo: true,
    );
    argParser.addOption(
      'destination',
      help: 'Download the package in this dir',
      defaultsTo: '.',
    );
    argParser.addOption(
      'repository',
      help: 'The package repository to download from',
      defaultsTo: cache.hosted.defaultUrl,
    );
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      usageException('Provide a package name');
    }
    if (argResults.rest.length > 1) {
      usageException('Please provide only a single package name');
    }
    final parts = argResults.rest[0].split(':');
    if (parts.length > 2) {
      usageException(
        'Use a single `:` to divide between package name and version.',
      );
    }
    final repository = argResults['repository'] as String;
    final name = parts[0];
    var versionString = parts.length == 2 ? parts[1] : null;

    final PackageId id;
    if (versionString == null) {
      final proposedId = await cache.getLatest(
        PackageRef(
          name,
          HostedDescription(
            name,
            repository,
          ),
        ),
      );
      if (proposedId == null) {
        fail('Could not find package $name');
      }
      id = proposedId;
    } else {
      final Version version;
      try {
        version = Version.parse(versionString);
      } on FormatException catch (e) {
        fail('Bad version string: ${e.message}');
      }
      id = PackageId(
        name,
        version,
        ResolvedHostedDescription(
          HostedDescription(
            name,
            repository,
          ),
          sha256: null // We don't know the content hash yet.
          ,
        ),
      );
    }
    final destinationArg = argResults['destination'] as String;
    final destinationDir = p.join(destinationArg, '$name-${id.version}');
    if (entryExists(destinationDir)) {
      fail('Target directory `$destinationDir` already exists.');
    }
    await log.progress(
      'Downloading $name ${id.version} to `$destinationDir`',
      () async {
        await cache.hosted.downloadInto(id, destinationDir, cache);
      },
    );
    final e = Entrypoint(
      destinationDir,
      cache,
    );
    if (argResults['resolve'] as bool) {
      try {
        await e.acquireDependencies(SolveType.get);
      } finally {
        log.message('To explore type: cd $destinationDir');
        if (e.example != null) {
          log.message('To explore the example type: cd ${e.example!.rootDir}');
        }
      }
    }
  }
}
