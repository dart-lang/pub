// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:collection/collection.dart' show maxBy;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pedantic/pedantic.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:stack_trace/stack_trace.dart';

import '../exceptions.dart';
import '../http.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../rate_limited_scheduler.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'cached.dart';

/// A package source that gets packages from a package hosting site that uses
/// the same API as pub.dartlang.org.
class HostedSource extends Source {
  @override
  final name = 'hosted';
  @override
  final hasMultipleVersions = true;

  @override
  BoundHostedSource bind(SystemCache systemCache, {bool isOffline = false}) =>
      isOffline
          ? _OfflineHostedSource(this, systemCache)
          : BoundHostedSource(this, systemCache);

  /// Gets the default URL for the package server for hosted dependencies.
  String get defaultUrl {
    // Changing this to pub.dev raises the following concerns:
    //
    //  1. It would blow through users caches.
    //  2. It would cause conflicts for users checking pubspec.lock into git, if using
    //     different versions of the dart-sdk / pub client.
    //  3. It might cause other problems (investigation needed) for pubspec.lock across
    //     different versions of the dart-sdk / pub client.
    //  4. It would expand the API surface we're committed to supporting long-term.
    //
    // Clearly, a bit of investigation is necessary before we update this to
    // pub.dev, it might be attractive to do next time we change the server API.
    return _defaultUrl ??= _pubHostedUrlConfig() ?? 'https://pub.dartlang.org';
  }

  String _defaultUrl;

  String _pubHostedUrlConfig() {
    var url = io.Platform.environment['PUB_HOSTED_URL'];
    if (url == null) return null;
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    var uri = Uri.parse(url);
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw ConfigException(
          '`PUB_HOSTED_URL` must have either the scheme "https://" or "http://". '
          '"$url" is invalid.');
    }
    return url;
  }

  /// Returns a reference to a hosted package named [name].
  ///
  /// If [url] is passed, it's the URL of the pub server from which the package
  /// should be downloaded. It can be a [Uri] or a [String].
  PackageRef refFor(String name, {url}) =>
      PackageRef(name, this, _descriptionFor(name, url));

  /// Returns an ID for a hosted package named [name] at [version].
  ///
  /// If [url] is passed, it's the URL of the pub server from which the package
  /// should be downloaded. It can be a [Uri] or a [String].
  PackageId idFor(String name, Version version, {url}) =>
      PackageId(name, this, version, _descriptionFor(name, url));

  /// Returns the description for a hosted package named [name] with the
  /// given package server [url].
  dynamic _descriptionFor(String name, [url]) {
    if (url == null) return name;

    if (url is! String && url is! Uri) {
      throw ArgumentError.value(url, 'url', 'must be a Uri or a String.');
    }

    return {'name': name, 'url': url.toString()};
  }

  @override
  String formatDescription(description) =>
      'on ${_parseDescription(description).last}';

  @override
  bool descriptionsEqual(description1, description2) =>
      _parseDescription(description1) == _parseDescription(description2);

  @override
  int hashDescription(description) => _parseDescription(description).hashCode;

  /// Ensures that [description] is a valid hosted package description.
  ///
  /// There are two valid formats. A plain string refers to a package with the
  /// given name from the default host, while a map with keys "name" and "url"
  /// refers to a package with the given name from the host at the given URL.
  @override
  PackageRef parseRef(String name, description, {String containingPath}) {
    _parseDescription(description);
    return PackageRef(name, this, description);
  }

  @override
  PackageId parseId(String name, Version version, description,
      {String containingPath}) {
    _parseDescription(description);
    return PackageId(name, this, version, description);
  }

  /// Parses the description for a package.
  ///
  /// If the package parses correctly, this returns a (name, url) pair. If not,
  /// this throws a descriptive FormatException.
  Pair<String, String> _parseDescription(description) {
    if (description is String) {
      return Pair<String, String>(description, defaultUrl);
    }

    if (description is! Map) {
      throw FormatException('The description must be a package name or map.');
    }

    if (!description.containsKey('name')) {
      throw FormatException("The description map must contain a 'name' key.");
    }

    var name = description['name'];
    if (name is! String) {
      throw FormatException("The 'name' key must have a string value.");
    }

    return Pair<String, String>(name, description['url'] ?? defaultUrl);
  }
}

/// Information about a package version retrieved from /api/packages/$package
class _VersionInfo {
  final Pubspec pubspec;
  final Uri archiveUrl;
  final PackageStatus status;

  _VersionInfo(this.pubspec, this.archiveUrl, this.status);
}

/// The [BoundSource] for [HostedSource].
class BoundHostedSource extends CachedSource {
  @override
  final HostedSource source;

  @override
  final SystemCache systemCache;
  RateLimitedScheduler<PackageRef, Map<PackageId, _VersionInfo>> _scheduler;

  BoundHostedSource(this.source, this.systemCache) {
    _scheduler = RateLimitedScheduler(
      _fetchVersions,
      maxConcurrentOperations: 10,
    );
  }

  Map<PackageId, _VersionInfo> _versionInfoFromPackageListing(
      Map body, PackageRef ref, Uri location) {
    final versions = body['versions'];
    if (versions is List) {
      return Map.fromEntries(versions.map((map) {
        final pubspecData = map['pubspec'];
        if (pubspecData is Map) {
          var pubspec = Pubspec.fromMap(pubspecData, systemCache.sources,
              expectedName: ref.name, location: location);
          var id = source.idFor(ref.name, pubspec.version,
              url: _serverFor(ref.description));
          var archiveUrl = map['archive_url'];
          if (archiveUrl is String) {
            final status = PackageStatus(
                isDiscontinued: body['isDiscontinued'] as bool ?? false,
                discontinuedReplacedBy: body['replacedBy'] as String);
            return MapEntry(
                id, _VersionInfo(pubspec, Uri.parse(archiveUrl), status));
          }
          throw FormatException('archive_url must be a String');
        }
        throw FormatException('pubspec must be a map');
      }));
    }
    throw FormatException('versions must be a list');
  }

  Future<Map<PackageId, _VersionInfo>> _fetchVersionsNoPrefetching(
      PackageRef ref) async {
    var url = _makeUrl(
        ref.description, (server, package) => '$server/api/packages/$package');
    log.io('Get versions from $url.');

    String bodyText;
    Map body;
    Map<PackageId, _VersionInfo> result;
    try {
      // TODO(sigurdm): Implement cancellation of requests. This probably
      // requires resolution of: https://github.com/dart-lang/sdk/issues/22265.
      bodyText = await httpClient.read(url, headers: pubApiHeaders);
      body = jsonDecode(bodyText);
      result = _versionInfoFromPackageListing(body, ref, url);
    } catch (error, stackTrace) {
      var parsed = source._parseDescription(ref.description);
      _throwFriendlyError(error, stackTrace, parsed.first, parsed.last);
    }

    // Cache the response on disk.
    // Don't cache overly big responses.
    if (body.length < 100 * 1024) {
      await _cacheVersionListingResponse(body, ref);
    }
    return result;
  }

  Future<Map<PackageId, _VersionInfo>> _fetchVersions(PackageRef ref) async {
    final preschedule =
        Zone.current[_prefetchingKey] as void Function(PackageRef);

    /// Prefetch the dependencies of the latest version, we are likely to need
    /// them later.
    void prescheduleDependenciesOfLatest(Map<PackageId, _VersionInfo> listing) {
      if (listing == null) return;
      final latestVersion =
          maxBy(listing.keys.map((id) => id.version), (e) => e);
      final latestVersionId =
          PackageId(ref.name, source, latestVersion, ref.description);
      final dependencies =
          listing[latestVersionId]?.pubspec?.dependencies?.values ?? [];
      unawaited(withDependencyType(DependencyType.none, () async {
        for (final packageRange in dependencies) {
          if (packageRange.source is HostedSource) {
            preschedule(packageRange.toRef());
          }
        }
      }));
    }

    if (preschedule != null) {
      /// If we have a cached response - preschedule dependencies of that.
      prescheduleDependenciesOfLatest(
        await _cachedVersionListingResponse(ref, Duration(days: 365)),
      );
    }
    final result = await _fetchVersionsNoPrefetching(ref);

    if (preschedule != null) {
      // Preschedule the dependencies from the actual response.
      // This might overlap with those from the cached response. But the
      // scheduler ensures each listing will be fetched at most once.
      prescheduleDependenciesOfLatest(result);
    }
    return result;
  }

  /// If a cached version listing response for [ref] exists on disk and is less
  /// than [maxAge] old it is parsed and returned.
  ///
  /// Otherwise deletes a cached response if it exists and returns `null`.
  Future<Map<PackageId, _VersionInfo>> _cachedVersionListingResponse(
      PackageRef ref, Duration maxAge) async {
    final cachePath = _versionListingCachePath(ref);
    final stat = await io.File(cachePath).stat();
    final now = DateTime.now();
    if (stat.type == io.FileSystemEntityType.file) {
      if (now.difference(stat.modified) < maxAge) {
        try {
          final cachedDoc = jsonDecode(await readTextFileAsync(cachePath));
          final timestamp = cachedDoc['_fetchedAt'];
          if (timestamp is String) {
            final cacheAge =
                DateTime.now().difference(DateTime.parse(timestamp));
            if (cacheAge > maxAge) {
              // Too old according to internal timestamp - delete.
              tryDeleteEntry(cachePath);
            } else {
              return _versionInfoFromPackageListing(
                cachedDoc,
                ref,
                Uri.file(cachePath),
              );
            }
          }
        } on io.IOException {
          // Could not read the file. Delete if it exists.
          tryDeleteEntry(cachePath);
        } on FormatException {
          // Decoding error - bad file or bad timestamp. Delete the file.
          tryDeleteEntry(cachePath);
        }
      } else {
        // File too old
        tryDeleteEntry(cachePath);
      }
    }
    return null;
  }

  /// Saves the (decoded) response from package-listing of [ref].
  Future<void> _cacheVersionListingResponse(Map body, PackageRef ref) async {
    final path = _versionListingCachePath(ref);
    try {
      ensureDir(p.dirname(path));
      await writeTextFileAsync(
        path,
        jsonEncode(
          <String, dynamic>{
            ...body,
            '_fetchedAt': DateTime.now().toIso8601String(),
          },
        ),
      );
    } on io.IOException catch (e) {
      // Not being able to write this cache is not fatal. Just move on...
      log.fine('Failed writing cache file. $e');
    }
  }

  @override
  Future<PackageStatus> status(PackageId id, Duration maxAge) async {
    final ref = id.toRef();
    // Did we already get info for this package?
    var versionListing = _scheduler.peek(ref);
    // Do we have a cached version response on disk?
    versionListing ??= await _cachedVersionListingResponse(ref, maxAge);
    // Otherwise retrieve the info from the host.
    versionListing ??= await _scheduler
        .schedule(ref)
        // Failures retrieving the listing here should just be ignored.
        .catchError(
          (_) => <PackageId, _VersionInfo>{},
          test: (error) => error is Exception,
        );

    final listing = versionListing[id];
    // If we don't have the specific version we return the empty response, since
    // it is more or less harmless..
    //
    // This can happen if the connection is broken, or the server is faulty.
    // We want to avoid a crash
    //
    // TODO(sigurdm): Consider representing the non-existence of the
    // package-version in the return value.
    return listing?.status ?? PackageStatus();
  }

  // The path where the response from the package-listing api is cached.
  String _versionListingCachePath(PackageRef ref) {
    final parsed = source._parseDescription(ref.description);
    final dir = _urlToDirectory(parsed.last);
    // Use a dot-dir because older versions of pub won't choke on that
    // name when iterating the cache (it is not listed by [listDir]).
    return p.join(systemCacheRoot, dir, _versionListingDirectory,
        '${ref.name}-versions.json');
  }

  static const _versionListingDirectory = '.cache';

  /// Downloads a list of all versions of a package that are available from the
  /// site.
  @override
  Future<List<PackageId>> doGetVersions(PackageRef ref, Duration maxAge) async {
    var versionListing = _scheduler.peek(ref);
    if (maxAge != null) {
      // Do we have a cached version response on disk?
      versionListing ??= await _cachedVersionListingResponse(ref, maxAge);
    }
    versionListing ??= await _scheduler.schedule(ref);
    return versionListing.keys.toList();
  }

  /// Parses [description] into its server and package name components, then
  /// converts that to a Uri given [pattern].
  ///
  /// Ensures the package name is properly URL encoded.
  Uri _makeUrl(
      description, String Function(String server, String package) pattern) {
    var parsed = source._parseDescription(description);
    var server = parsed.last;
    var package = Uri.encodeComponent(parsed.first);
    return Uri.parse(pattern(server, package));
  }

  /// Retrieves the pubspec for a specific version of a package that is
  /// available from the site.
  @override
  Future<Pubspec> describeUncached(PackageId id) async {
    final versions = await _scheduler.schedule(id.toRef());
    final url = _makeUrl(
        id.description, (server, package) => '$server/api/packages/$package');
    return versions[id]?.pubspec ??
        (throw PackageNotFoundException('Could not find package $id at $url'));
  }

  /// Downloads the package identified by [id] to the system cache.
  @override
  Future<Package> downloadToSystemCache(PackageId id) async {
    if (!isInSystemCache(id)) {
      var packageDir = getDirectory(id);
      ensureDir(p.dirname(packageDir));
      await _download(id, packageDir);
    }

    return Package.load(id.name, getDirectory(id), systemCache.sources);
  }

  /// The system cache directory for the hosted source contains subdirectories
  /// for each separate repository URL that's used on the system.
  ///
  /// Each of these subdirectories then contains a subdirectory for each
  /// package downloaded from that site.
  @override
  String getDirectory(PackageId id) {
    var parsed = source._parseDescription(id.description);
    var dir = _urlToDirectory(parsed.last);
    return p.join(systemCacheRoot, dir, '${parsed.first}-${id.version}');
  }

  /// Re-downloads all packages that have been previously downloaded into the
  /// system cache from any server.
  @override
  Future<Iterable<RepairResult>> repairCachedPackages() async {
    if (!dirExists(systemCacheRoot)) return [];

    return (await Future.wait(listDir(systemCacheRoot).map(
      (serverDir) async {
        var url = _directoryToUrl(p.basename(serverDir));
        final results = <RepairResult>[];
        var packages = <Package>[];
        for (var entry in listDir(serverDir)) {
          try {
            packages.add(Package.load(null, entry, systemCache.sources));
          } catch (error, stackTrace) {
            log.error('Failed to load package', error, stackTrace);
            results.add(
              RepairResult(
                _idForBasename(
                  p.basename(entry),
                  url: _directoryToUrl(serverDir),
                ),
                success: false,
              ),
            );
            tryDeleteEntry(entry);
          }
        }

        // Delete the cached package listings.
        tryDeleteEntry(p.join(serverDir, _versionListingDirectory));

        packages.sort(Package.orderByNameAndVersion);

        return results
          ..addAll(await Future.wait(
            packages.map(
              (package) async {
                var id = source.idFor(package.name, package.version, url: url);
                try {
                  await _download(id, package.dir);
                  return RepairResult(id, success: true);
                } catch (error, stackTrace) {
                  var message = 'Failed to repair ${log.bold(package.name)} '
                      '${package.version}';
                  if (url != source.defaultUrl) message += ' from $url';
                  log.error('$message. Error:\n$error');
                  log.fine(stackTrace);

                  tryDeleteEntry(package.dir);
                  return RepairResult(id, success: false);
                }
              },
            ),
          ));
      },
    )))
        .expand((x) => x);
  }

  /// Returns the best-guess package ID for [basename], which should be a
  /// subdirectory in a hosted cache.
  PackageId _idForBasename(String basename, {String url}) {
    var components = split1(basename, '-');
    var version = Version.none;
    if (components.length > 1) {
      try {
        version = Version.parse(components.last);
      } catch (_) {
        // Default to Version.none.
      }
    }
    final name = components.first;
    return source.idFor(name, version, url: url);
  }

  bool _looksLikePackageDir(String path) =>
      dirExists(path) &&
      _idForBasename(p.basename(path)).version != Version.none;

  /// Gets all of the packages that have been downloaded into the system cache
  /// from the default server.
  @override
  List<Package> getCachedPackages() {
    var cacheDir = p.join(systemCacheRoot, _urlToDirectory(source.defaultUrl));
    if (!dirExists(cacheDir)) return [];

    return listDir(cacheDir)
        .where(_looksLikePackageDir)
        .map((entry) {
          try {
            return Package.load(null, entry, systemCache.sources);
          } catch (error, stackTrace) {
            log.fine('Failed to load package from $entry:\n'
                '$error\n'
                '${Chain.forTrace(stackTrace)}');
            return null;
          }
        })
        .where((e) => e != null)
        .toList();
  }

  /// Downloads package [package] at [version] from the archive_url and unpacks
  /// it into [destPath].
  ///
  /// If there is no archive_url, try to fetch it from
  /// `$server/packages/$package/versions/$version.tar.gz` where server comes
  /// from `id.description`.
  Future _download(PackageId id, String destPath) async {
    final versions = await _scheduler.schedule(id.toRef());
    final versionInfo = versions[id];
    final packageName = id.name;
    final version = id.version;
    if (versionInfo == null) {
      throw PackageNotFoundException(
          'Package $packageName has no version $version');
    }
    var url = versionInfo.archiveUrl;
    if (url == null) {
      // To support old servers that has no archive_url we fall back to the
      // hard-coded path.
      final parsedDescription = source._parseDescription(id.description);
      final server = parsedDescription.last;
      url = Uri.parse('$server/packages/$packageName/versions/$version.tar.gz');
    }
    log.io('Get package from $url.');
    log.fine('Downloading ${log.bold(id.name)} ${id.version}...');

    // Download and extract the archive to a temp directory.
    var tempDir = systemCache.createTempDir();
    var response = await httpClient.send(http.Request('GET', url));
    await extractTarGz(response.stream, tempDir);

    // Remove the existing directory if it exists. This will happen if
    // we're forcing a download to repair the cache.
    if (dirExists(destPath)) deleteEntry(destPath);

    // Now that the get has succeeded, move it to the real location in the
    // cache. This ensures that we don't leave half-busted ghost
    // directories in the user's pub cache if a get fails.
    renameDir(tempDir, destPath);
  }

  /// When an error occurs trying to read something about [package] from [url],
  /// this tries to translate into a more user friendly error message.
  ///
  /// Always throws an error, either the original one or a better one.
  void _throwFriendlyError(
      error, StackTrace stackTrace, String package, String url) {
    if (error is PubHttpException) {
      if (error.response.statusCode == 404) {
        throw PackageNotFoundException(
            'could not find package $package at $url',
            innerError: error,
            innerTrace: stackTrace);
      }

      fail(
          '${error.response.statusCode} ${error.response.reasonPhrase} trying '
          'to find package $package at $url.',
          error,
          stackTrace);
    } else if (error is io.SocketException) {
      fail('Got socket error trying to find package $package at $url.', error,
          stackTrace);
    } else if (error is io.TlsException) {
      fail('Got TLS error trying to find package $package at $url.', error,
          stackTrace);
    } else if (error is FormatException) {
      throw PackageNotFoundException(
          'Got badly formatted response trying to find package $package at $url',
          innerError: error,
          innerTrace: stackTrace);
    } else {
      // Otherwise re-throw the original exception.
      throw error;
    }
  }

  /// Given a URL, returns a "normalized" string to be used as a directory name
  /// for packages downloaded from the server at that URL.
  ///
  /// This normalization strips off the scheme (which is presumed to be HTTP or
  /// HTTPS) and *sort of* URL-encodes it. I say "sort of" because it does it
  /// incorrectly: it uses the character's *decimal* ASCII value instead of hex.
  ///
  /// This could cause an ambiguity since some characters get encoded as three
  /// digits and others two. It's possible for one to be a prefix of the other.
  /// In practice, the set of characters that are encoded don't happen to have
  /// any collisions, so the encoding is reversible.
  ///
  /// This behavior is a bug, but is being preserved for compatibility.
  String _urlToDirectory(String url) {
    // Normalize all loopback URLs to "localhost".
    url = url.replaceAllMapped(
        RegExp(r'^(https?://)(127\.0\.0\.1|\[::1\]|localhost)?'), (match) {
      // Don't include the scheme for HTTPS URLs. This makes the directory names
      // nice for the default and most recommended scheme. We also don't include
      // it for localhost URLs, since they're always known to be HTTP.
      var localhost = match[2] == null ? '' : 'localhost';
      var scheme =
          match[1] == 'https://' || localhost.isNotEmpty ? '' : match[1];
      return '$scheme$localhost';
    });
    return replace(
        url, RegExp(r'[<>:"\\/|?*%]'), (match) => '%${match[0].codeUnitAt(0)}');
  }

  /// Given a directory name in the system cache, returns the URL of the server
  /// whose packages it contains.
  ///
  /// See [_urlToDirectory] for details on the mapping. Note that because the
  /// directory name does not preserve the scheme, this has to guess at it. It
  /// chooses "http" for loopback URLs (mainly to support the pub tests) and
  /// "https" for all others.
  String _directoryToUrl(String url) {
    // Decode the pseudo-URL-encoded characters.
    var chars = '<>:"\\/|?*%';
    for (var i = 0; i < chars.length; i++) {
      var c = chars.substring(i, i + 1);
      url = url.replaceAll('%${c.codeUnitAt(0)}', c);
    }

    // If the URL has an explicit scheme, use that.
    if (url.contains('://')) return url;

    // Otherwise, default to http for localhost and https for everything else.
    var scheme =
        isLoopback(url.replaceAll(RegExp(':.*'), '')) ? 'http' : 'https';
    return '$scheme://$url';
  }

  /// Returns the server URL for [description].
  Uri _serverFor(description) =>
      Uri.parse(source._parseDescription(description).last);

  /// Enables speculative prefetching of dependencies of packages queried with
  /// [getVersions].
  Future<T> withPrefetching<T>(Future<T> Function() callback) async {
    return await _scheduler.withPrescheduling((preschedule) async {
      return await runZoned(callback,
          zoneValues: {_prefetchingKey: preschedule});
    });
  }

  /// Key for storing the current prefetch function in the current [Zone].
  static const _prefetchingKey = #_prefetch;
}

/// This is the modified hosted source used when pub get or upgrade are run
/// with "--offline".
///
/// This uses the system cache to get the list of available packages and does
/// no network access.
class _OfflineHostedSource extends BoundHostedSource {
  _OfflineHostedSource(HostedSource source, SystemCache systemCache)
      : super(source, systemCache);

  /// Gets the list of all versions of [ref] that are in the system cache.
  @override
  Future<List<PackageId>> doGetVersions(PackageRef ref, Duration maxAge) async {
    var parsed = source._parseDescription(ref.description);
    var server = parsed.last;
    log.io('Finding versions of ${ref.name} in '
        '$systemCacheRoot/${_urlToDirectory(server)}');

    var dir = p.join(systemCacheRoot, _urlToDirectory(server));

    List<PackageId> versions;
    if (dirExists(dir)) {
      versions = listDir(dir)
          .where(_looksLikePackageDir)
          .map((entry) => _idForBasename(p.basename(entry), url: server))
          .where((id) => id.name == ref.name && id.version != Version.none)
          .toList();
    } else {
      versions = [];
    }

    // If there are no versions in the cache, report a clearer error.
    if (versions.isEmpty) {
      throw PackageNotFoundException(
          'could not find package ${ref.name} in cache');
    }

    return versions;
  }

  @override
  Future _download(PackageId id, String destPath) {
    // Since HostedSource is cached, this will only be called for uncached
    // packages.
    throw UnsupportedError('Cannot download packages when offline.');
  }

  @override
  Future<Pubspec> describeUncached(PackageId id) {
    throw PackageNotFoundException(
        '${id.name} ${id.version} is not available in your system cache');
  }

  @override
  Future<PackageStatus> status(PackageId id, Duration maxAge) async {
    // Do we have a cached version response on disk?
    final versionListing =
        await _cachedVersionListingResponse(id.toRef(), maxAge);

    if (versionListing == null) {
      return PackageStatus();
    }
    final listing = versionListing[id];
    // If we don't have the specific version we return the empty response.
    //
    // This should not happen. But in production we want to avoid a crash, since
    // it is more or less harmless.
    //
    // TODO(sigurdm): Consider representing the non-existence of the
    // package-version in the return value.
    assert(listing != null);
    return versionListing[id]?.status ?? PackageStatus();
  }
}
