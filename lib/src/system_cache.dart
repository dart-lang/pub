// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'authentication/token_store.dart';
import 'exceptions.dart';
import 'io.dart';
import 'io.dart' as io show createTempDir;
import 'log.dart' as log;
import 'package.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'source.dart';
import 'source/cached.dart';
import 'source/git.dart';
import 'source/hosted.dart';
import 'source/path.dart';
import 'source/sdk.dart';
import 'source/unknown.dart';
import 'utils.dart';

/// The system-wide cache of downloaded packages.
///
/// This cache contains all packages that are downloaded from the internet.
/// Packages that are available locally (e.g. path dependencies) don't use this
/// cache.
class SystemCache {
  /// The root directory where this package cache is located.
  String get rootDir => _rootDir ??= defaultDir;
  String? _rootDir;

  String rootDirForSource(CachedSource source) => p.join(rootDir, source.name);

  String get tempDir => p.join(rootDir, '_temp');

  static String defaultDir = (() {
    if (Platform.environment.containsKey('PUB_CACHE')) {
      return p.absolute(Platform.environment['PUB_CACHE']!);
    } else if (Platform.isWindows) {
      // %LOCALAPPDATA% is used as the cache location over %APPDATA%, because
      // the latter is synchronised between devices when the user roams between
      // them, whereas the former is not.
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null) {
        dataError('''
Could not find the pub cache. No `LOCALAPPDATA` environment variable exists.
Consider setting the `PUB_CACHE` variable manually.
''');
      }
      return p.join(localAppData, 'Pub', 'Cache');
    } else {
      final home = Platform.environment['HOME'];
      if (home == null) {
        dataError('''
Could not find the pub cache. No `HOME` environment variable exists.
Consider setting the `PUB_CACHE` variable manually.
''');
      }
      return p.join(home, '.pub-cache');
    }
  })();

  /// The available sources.
  late final _sources = Map<String, Source>.fromIterable(
    [hosted, git, path, sdk],
    key: (source) => (source as Source).name,
  );

  Source sources(String? name) {
    return name == null
        ? defaultSource
        : (_sources[name] ?? UnknownSource(name));
  }

  Source get defaultSource => hosted;

  /// The built-in Git source.
  GitSource get git => GitSource.instance;

  /// The built-in hosted source.
  HostedSource get hosted => HostedSource.instance;

  /// The built-in path source bound to this cache.
  PathSource get path => PathSource.instance;

  /// The built-in SDK source bound to this cache.
  SdkSource get sdk => SdkSource.instance;

  /// The default credential store.
  /// TODO(sigurdm): this does not really belong in the cache.
  final TokenStore tokenStore;

  /// If true, cached sources will attempt to use the cached packages for
  /// resolution.
  final bool isOffline;

  /// Creates a system cache and registers all sources in [sources].
  ///
  /// If [isOffline] is `true`, then the offline hosted source will be used.
  /// Defaults to `false`.
  SystemCache({String? rootDir, this.isOffline = false})
      : _rootDir = rootDir,
        tokenStore = TokenStore(dartConfigDir);

  /// Loads the package identified by [id].
  ///
  /// Throws an [ArgumentError] if [id] has an invalid source.
  Package load(PackageId id) {
    return Package.load(
      getDirectory(id),
      loadPubspec: Pubspec.loadRootWithSources(sources),
      expectedName: id.name,
    );
  }

  /// Create a new temporary directory within the system cache.
  ///
  /// The system cache maintains its own temporary directory that it uses to
  /// stage packages into while downloading. It uses this instead of the OS's
  /// system temp directory to ensure that it's on the same volume as the pub
  /// system cache so that it can move the directory from it.
  String createTempDir() {
    final temp = ensureDir(tempDir);
    return io.createTempDir(temp, 'dir');
  }

  /// Deletes the system cache's internal temp directory.
  void deleteTempDir() {
    log.fine('Clean up system cache temp directory $tempDir.');
    if (dirExists(tempDir)) deleteEntry(tempDir);
  }

  /// An in-memory cache of pubspecs described by [describe].
  final cachedPubspecs = <PackageId, Pubspec>{};

  /// Loads the (possibly remote) pubspec for the package version identified by
  /// [id].
  ///
  /// This may be called for packages that have not yet been downloaded during
  /// the version resolution process. Its results are automatically memoized.
  ///
  /// Throws a [DataException] if the pubspec's version doesn't match [id]'s
  /// version.
  Future<Pubspec> describe(PackageId id) async {
    final pubspec = cachedPubspecs[id] ??= await id.source.doDescribe(id, this);
    if (pubspec.version != id.version) {
      throw PackageNotFoundException(
        'the pubspec for $id has version ${pubspec.version}',
      );
    }
    return pubspec;
  }

  /// Get the IDs of all versions that match [ref].
  ///
  /// Note that this does *not* require the packages to be downloaded locally,
  /// which is the point. This is used during version resolution to determine
  /// which package versions are available to be downloaded (or already
  /// downloaded).
  ///
  /// By default, this assumes that each description has a single version and
  /// uses [describe] to get that version.
  ///
  /// If [maxAge] is given answers can be taken from cache - up to that age old.
  ///
  /// If given, the [allowedRetractedVersion] is the only version which can be
  /// selected even if it is marked as retracted. Otherwise, all the returned
  /// IDs correspond to non-retracted versions.
  Future<List<PackageId>> getVersions(
    PackageRef ref, {
    Duration? maxAge,
    Version? allowedRetractedVersion,
  }) async {
    var versions = await ref.source.doGetVersions(ref, maxAge, this);

    versions = (await Future.wait(
      versions.map((id) async {
        final packageStatus = await ref.source.status(
          id.toRef(),
          id.version,
          this,
          maxAge: maxAge,
        );
        if (!packageStatus.isRetracted ||
            id.version == allowedRetractedVersion) {
          return id;
        }
        return null;
      }),
    ))
        .nonNulls
        .toList();

    return versions;
  }

  /// Returns the directory where this package can (or could) be found locally.
  ///
  /// If the source is cached, this will be a path in the system cache.
  ///
  /// If id is a relative path id, the directory will be relative from
  /// [relativeFrom]. Returns an absolute path if [relativeFrom] is not passed.
  String getDirectory(PackageId id, {String? relativeFrom}) {
    return id.source.doGetDirectory(id, this, relativeFrom: relativeFrom);
  }

  /// Downloads a cached package identified by [id] to the cache.
  ///
  /// [id] must refer to a cached package.
  ///
  /// If [allowOutdatedHashChecks] is `true` we use a cached version listing
  /// response if present instead of probing the server. Not probing allows for
  /// `pub get` with a filled cache to be a fast case that doesn't require any
  /// new version-listings.
  ///
  /// Returns [id] with an updated [ResolvedDescription], this can be different
  /// if the content-hash changed while downloading.
  Future<DownloadPackageResult> downloadPackage(PackageId id) async {
    final source = id.source;
    assert(source is CachedSource);
    final result = await (source as CachedSource).downloadToSystemCache(
      id,
      this,
    );

    // We only update the README.md in the cache when a change to the cache has
    // happened. This is:
    // * to avoid failing if used with a read-only cache, and
    // * because the cost of writing a single file is negligible compared to
    //   downloading a package, but might be significant in the fast-case where
    //   a the cache is already valid.
    if (result.didUpdate) {
      maintainCache();
    }
    return result;
  }

  /// Get the latest version of [package].
  ///
  /// Will consider _prereleases_ if:
  ///  * [allowPrereleases] is true, or,
  ///  * If [version] is non-null and is a prerelease version and there are no
  ///    later stable version we return a prerelease version if it exists.
  ///
  /// Returns `null`, if unable to find the package or if [package] is `null`.
  Future<PackageId?> getLatest(
    PackageRef? package, {
    Version? version,
    bool allowPrereleases = false,
  }) async {
    if (package == null) {
      return null;
    }

    final List<PackageId> available;
    try {
      // TODO: Pass some maxAge to getVersions
      available = await getVersions(package);
    } on PackageNotFoundException {
      return null;
    }
    if (available.isEmpty) {
      return null;
    }

    available.sort(
      allowPrereleases
          ? (x, y) => x.version.compareTo(y.version)
          : (x, y) => Version.prioritize(x.version, y.version),
    );
    var latest = available.last;

    if (version != null && version.isPreRelease && version > latest.version) {
      available.sort((x, y) => x.version.compareTo(y.version));
      latest = available.last;
    }

    // There should be exactly one entry in [available] matching [latest]
    assert(available.where((id) => id.version == latest.version).length == 1);

    return latest;
  }

  /// Removes all contents of the system cache.
  ///
  /// Rewrites the README.md.
  void clean() {
    deleteEntry(rootDir);
    ensureDir(rootDir);
    maintainCache();
  }

  /// Tasks that ensures the cache is in a good condition.
  /// Should be called whenever an operation updates the cache.
  void maintainCache() {
    /// We only want to do this once per run.
    if (_hasMaintainedCache) return;
    _hasMaintainedCache = true;
    _ensureReadme();
    _checkOldCacheLocation();
  }

  /// Check for the presence of a cache at the legacy location
  /// `%APPDATA$\Pub\Cache`.
  ///
  /// If it is present, give a warning and write a DEPRECATED.md in that cache.
  ///
  /// If DEPRECATED.md is less than 7 days old, we don't repeat the warning.
  void _checkOldCacheLocation() {
    // Background:
    // Prior to Dart 2.8 the default location for the PUB_CACHE on Windows was:
    //   %APPDATA%\Pub\Cache
    //
    // Start Dart 2.8 pub started migrating the default PUB_CACHE location to:
    //   %LOCALAPPDATA%\Pub\Cache
    // That is:
    //  * If a pub-cache existed in `%LOCALAPPDATA%\Pub\Cache` then it
    //    would be used.
    //  * If a pub-cache existed in `%APPDATA%\Pub\Cache` then it would be
    //    used, unless a pub-cache in `%LOCALAPPDATA%\Pub\Cache` had been found.
    //  * If no pub-cache was found, a new empty pub-cache was created in
    //    `%LOCALAPPDATA%\Pub\Cache`.
    //
    // Starting in Dart 3.0 pub will no-longer look for a pub-cache in
    // `%APPDATA%\Pub\Cache`. Instead it will always use the new location,
    // `%LOCALAPPDATA%\Pub\Cache`, as default PUB_CACHE location.
    //
    // Using `%APPDATA%` caused the pub-cache to be copied with the user-profile,
    // when using a networked Windows setup where users can login on multiple
    // machines. This is undesirable because you are moving a lot of bytes over
    // the network and onto whatever servers are storing the user profiles.
    //
    // Thus, we migrated to storing the pub-cache in `%LOCALAPPDATA%`.
    // And finished the migration in Dart 3 to keep things simple.
    if (!Platform.isWindows) return;

    final appData = Platform.environment['APPDATA'];
    if (appData == null) return;
    final legacyCacheLocation = p.join(appData, 'Pub', 'Cache');
    final legacyCacheDeprecatedFile =
        p.join(legacyCacheLocation, 'DEPRECATED.md');
    final stat = tryStatFile(legacyCacheDeprecatedFile);
    if ((stat == null ||
            DateTime.now().difference(stat.changed) > Duration(days: 7)) &&
        dirExists(legacyCacheLocation)) {
      log.warning('''
Found a legacy Pub cache at $legacyCacheLocation. Pub is using $defaultDir.

Consider deleting the legacy cache.

See https://dart.dev/resources/dart-3-migration#other-tools-changes for details.
''');
      try {
        writeTextFile(legacyCacheDeprecatedFile, '''
As of Dart 3 this pub cache is no longer used by Dart/Flutter.

Consider deleting it, if you are not using Dart versions earlier than 2.8.0.

See https://dart.dev/resources/dart-3-migration#other-tools-changes for details.
''');
      } on Exception catch (e) {
        // Failing to write the DEPRECATED.md file should not disrupt other
        // operations.
        log.fine('Failed to write $legacyCacheDeprecatedFile: $e');
      }
    }
  }

  /// Write a README.md file in the root of the cache directory to document the
  /// contents of the folder.
  ///
  /// This should only be called when we are doing another operation that is
  /// modifying the `PUB_CACHE`. This ensures that users won't experience
  /// permission errors because we writing a `README.md` file, in a flow that
  /// the user expected wouldn't have issues with a read-only `PUB_CACHE`.
  void _ensureReadme() {
    final readmePath = p.join(rootDir, 'README.md');
    try {
      writeTextFile(readmePath, '''
Pub Package Cache
=================

This folder is used by Pub to store cached packages used in Dart / Flutter
projects.

The contents of this folder should only be modified using the `dart pub` and
`flutter pub` commands.

Modifying this folder manually can lead to inconsistent behavior.

For details on how manage the `PUB_CACHE`, see:
https://dart.dev/go/pub-cache
''');
    } on Exception catch (e) {
      // Failing to write the README.md should not disrupt other operations.
      log.fine('Failed to write README.md in PUB_CACHE: $e');
    }
  }

  bool _hasMaintainedCache = false;
}

typedef SourceRegistry = Source Function(String? name);
