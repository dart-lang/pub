// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../command.dart';
import '../io.dart' as io;
import '../log.dart' as log;
import '../package_name.dart';
import '../source/hosted.dart';
import '../utils.dart';

/// Handles the `download` pub command.
class DownloadCommand extends PubCommand {
  @override
  String get name => 'download';
  @override
  String get description => 'Download a package to local storage.'
      ' Pass --example to get just the example.\n\n';
  @override
  String get argumentsDescription => 'package-name';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-download';

  DownloadCommand() {
    argParser.addFlag(
      'example',
      abbr: 'e',
      negatable: false,
      help: 'Download just the /example folder of the package.',
    );
    argParser.addOption(
      'hosted-url',
      help: 'URL of package host server',
      hide: true,
    );
    argParser.addOption(
      'destination',
      abbr: 'd',
      help: 'The destination directory to download to.'
          ' Defaults to a directory called <package name>-<package version>'
          ' located in the current working directory.',
    );
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty || argResults.rest.length != 1) {
      usageException('Must specify one package to download.');
    }

    // Locate the package, and it's most recent stable version.
    final packageName = argResults.rest[0];
    final ref = PackageRef(
      packageName,
      HostedDescription(
        packageName,
        argResults.hostedUrl ?? cache.hosted.defaultUrl,
      ),
    );
    final packageId = await cache.getLatest(ref);
    if (packageId == null) {
      fail("Error: Could not find package '$packageName'");
    }

    // Copy from the cache to the destination directory.
    var dirName = argResults.destination ??
        '${packageId.name}-${packageId.version}'
            '${argResults.example ? '-example' : ''}';
    if (io.dirExists(dirName)) {
      fail("Error: Destination directory '$dirName' already exists!");
    }

    log.message("Downloading ${argResults.example ? 'the example of ' : ''}"
        "package '${packageId.name}' v${packageId.version} "
        "to '$dirName'...");
    final cacheDir = cache.getDirectory(packageId);
    final sourceDir =
        !argResults.example ? cacheDir : p.join(cacheDir, 'example');
    final result = io.dirCopy(Directory(sourceDir), Directory(dirName));
    if (result != null) {
      fail(result);
    }
  }
}

extension on ArgResults {
  bool get example => flag('example');
  String? get hostedUrl => this['hosted-url'] as String?;
  String? get destination => this['destination'] as String?;
}
