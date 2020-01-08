// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'io.dart';
import 'io.dart' as io show createTempDir;
import 'log.dart' as log;
import 'package.dart';
import 'package_name.dart';
import 'source.dart';
import 'source/cached.dart';
import 'source/git.dart';
import 'source/hosted.dart';
import 'source/path.dart';
import 'source/sdk.dart';
import 'source/unknown.dart';
import 'source_registry.dart';

/// The system-wide cache of downloaded packages.
///
/// This cache contains all packages that are downloaded from the internet.
/// Packages that are available locally (e.g. path dependencies) don't use this
/// cache.
class SystemCache {
  /// The root directory where this package cache is located.
  final String rootDir;

  String get tempDir => p.join(rootDir, '_temp');

  static String defaultDir = (() {
    if (Platform.environment.containsKey('PUB_CACHE')) {
      return Platform.environment['PUB_CACHE'];
    } else if (Platform.isWindows) {
      // %LOCALAPPDATA% is preferred as the cache location over %APPDATA%, because the latter is synchronised between
      // devices when the user roams between them, whereas the former is not.
      // The default cache dir used to be in %APPDATA%, so to avoid breaking old installs,
      // we use the old dir in %APPDATA% if it exists. Else, we use the new default location
      // in %LOCALAPPDATA%.
      var appData = Platform.environment['APPDATA'];
      var appDataCacheDir = p.join(appData, 'Pub', 'Cache');
      if (dirExists(appDataCacheDir)) {
        return appDataCacheDir;
      }
      var localAppData = Platform.environment['LOCALAPPDATA'];
      return p.join(localAppData, 'Pub', 'Cache');
    } else {
      return '${Platform.environment['HOME']}/.pub-cache';
    }
  })();

  /// The registry for sources used by this system cache.
  ///
  /// New sources registered here will be available through the [source]
  /// function.
  final sources = SourceRegistry();

  /// The sources bound to this cache.
  final _boundSources = <Source, BoundSource>{};

  /// The built-in Git source bound to this cache.
  BoundGitSource get git => _boundSources[sources.git] as BoundGitSource;

  /// The built-in hosted source bound to this cache.
  BoundHostedSource get hosted =>
      _boundSources[sources.hosted] as BoundHostedSource;

  /// The built-in path source bound to this cache.
  BoundPathSource get path => _boundSources[sources.path] as BoundPathSource;

  /// The built-in SDK source bound to this cache.
  BoundSdkSource get sdk => _boundSources[sources.sdk] as BoundSdkSource;

  /// The default source bound to this cache.
  BoundSource get defaultSource => source(sources[null]);

  /// Creates a system cache and registers all sources in [sources].
  ///
  /// If [isOffline] is `true`, then the offline hosted source will be used.
  /// Defaults to `false`.
  SystemCache({String rootDir, bool isOffline = false})
      : rootDir = rootDir ?? SystemCache.defaultDir {
    for (var source in sources.all) {
      if (source is HostedSource) {
        _boundSources[source] = source.bind(this, isOffline: isOffline);
      } else {
        _boundSources[source] = source.bind(this);
      }
    }
  }

  /// Returns the version of [source] bound to this cache.
  BoundSource source(Source source) =>
      _boundSources.putIfAbsent(source, () => source.bind(this));

  /// Loads the package identified by [id].
  ///
  /// Throws an [ArgumentError] if [id] has an invalid source.
  Package load(PackageId id) {
    if (id.source is UnknownSource) {
      throw ArgumentError('Unknown source ${id.source}.');
    }

    return Package.load(id.name, source(id.source).getDirectory(id), sources);
  }

  /// Determines if the system cache contains the package identified by [id].
  bool contains(PackageId id) {
    var source = this.source(id.source);

    if (source is CachedSource) return source.isInSystemCache(id);
    throw ArgumentError('Package $id is not cacheable.');
  }

  /// Create a new temporary directory within the system cache.
  ///
  /// The system cache maintains its own temporary directory that it uses to
  /// stage packages into while downloading. It uses this instead of the OS's
  /// system temp directory to ensure that it's on the same volume as the pub
  /// system cache so that it can move the directory from it.
  String createTempDir() {
    var temp = ensureDir(tempDir);
    return io.createTempDir(temp, 'dir');
  }

  /// Deletes the system cache's internal temp directory.
  void deleteTempDir() {
    log.fine('Clean up system cache temp directory $tempDir.');
    if (dirExists(tempDir)) deleteEntry(tempDir);
  }
}
