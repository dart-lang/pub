// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../io.dart';
import '../log.dart' as log;
import '../source/hosted.dart';
import '../utils.dart';

/// Handles the `cache preload` pub command.
class CachePreloadCommand extends PubCommand {
  @override
  String get name => 'preload';
  @override
  String get description => 'Install packages from a .tar.gz archive.';
  @override
  String get argumentsDescription => '<package1.tar.gz> ...';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-cache';

  /// The `cache preload` command is hidden by default, because it's really only intended for
  /// `flutter` to use when pre-loading `PUB_CACHE` after being installed from `zip` archive.
  @override
  bool get hidden => true;

  @override
  Future<void> runProtected() async {
    // Make sure there is a package.
    if (argResults.rest.isEmpty) {
      usageException('No package to preload given.');
    }

    for (String packagePath in argResults.rest) {
      if (!fileExists(packagePath)) {
        fail('Could not find file $packagePath.');
      }
    }
    for (String archivePath in argResults.rest) {
      final id = await cache.hosted.preloadPackage(archivePath, cache);
      final url = (id.description.description as HostedDescription).url;

      final fromPart = HostedSource.isFromPubDev(id) ? '' : ' from $url';
      log.message('Installed $archivePath in cache as $id$fromPart.');
    }
  }
}
