// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:collection/collection.dart'
    show maxBy, IterableNullableExtension;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stack_trace/stack_trace.dart';

import '../authentication/client.dart';
import '../exceptions.dart';
import '../http.dart';
import '../io.dart';
import '../language_version.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../rate_limited_scheduler.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'cached.dart';

/// Validates and normalizes a [hostedUrl] which is pointing to a pub server.
///
/// A [hostedUrl] is a URL pointing to a _hosted pub server_ as defined by the
/// [repository-spec-v2][1]. The default value is `pub.dartlang.org`, and can be
/// overwritten using `PUB_HOSTED_URL`. It can also specified for individual
/// hosted-dependencies in `pubspec.yaml`, and for the root package using the
/// `publish_to` key.
///
/// The [hostedUrl] is always normalized to a [Uri] with path that ends in slash
/// unless the path is merely `/`, in which case we normalize to the bare domain
/// this keeps the [hostedUrl] and maintains avoids unnecessary churn in
/// `pubspec.lock` files which contain `https://pub.dartlang.org`.
///
/// Throws [FormatException] if there is anything wrong [hostedUrl].
///
/// [1]: ../../../doc/repository-spec-v2.md
Uri validateAndNormalizeHostedUrl(String hostedUrl) {
  Uri u;
  try {
    u = Uri.parse(hostedUrl);
  } on FormatException catch (e) {
    throw FormatException(
      'invalid url: ${e.message}',
      e.source,
      e.offset,
    );
  }
  if (!u.hasScheme || (u.scheme != 'http' && u.scheme != 'https')) {
    throw FormatException('url scheme must be https:// or http://', hostedUrl);
  }
  if (!u.hasAuthority || u.host == '') {
    throw FormatException('url must have a hostname', hostedUrl);
  }
  if (u.userInfo != '') {
    throw FormatException('user-info is not supported in url', hostedUrl);
  }
  if (u.hasQuery) {
    throw FormatException('querystring is not supported in url', hostedUrl);
  }
  if (u.hasFragment) {
    throw FormatException('fragment is not supported in url', hostedUrl);
  }
  u = u.normalizePath();
  // If we have a path of only `/`
  if (u.path == '/') {
    u = u.replace(path: '');
  }
  // If there is a path, and it doesn't end in a slash we normalize to slash
  if (u.path.isNotEmpty && !u.path.endsWith('/')) {
    u = u.replace(path: u.path + '/');
  }
  return u;
}

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

  static String pubDevUrl = 'https://pub.dartlang.org';

  static bool isFromPubDev(PackageId id) {
    return id.source is HostedSource &&
        (id.description as _HostedDescription).uri.toString() == pubDevUrl;
  }

  /// Gets the default URL for the package server for hosted dependencies.
  Uri get defaultUrl {
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
    try {
      return _defaultUrl ??= validateAndNormalizeHostedUrl(
        io.Platform.environment['PUB_HOSTED_URL'] ?? 'https://pub.dartlang.org',
      );
    } on FormatException catch (e) {
      throw ConfigException(
          'Invalid `PUB_HOSTED_URL="${e.source}"`: ${e.message}');
    }
  }

  Uri? _defaultUrl;

  /// Returns a reference to a hosted package named [name].
  ///
  /// If [url] is passed, it's the URL of the pub server from which the package
  /// should be downloaded. [url] most be normalized and validated using
  /// [validateAndNormalizeHostedUrl].
  PackageRef refFor(String name, {Uri? url}) =>
      PackageRef(name, this, _HostedDescription(name, url ?? defaultUrl));

  /// Returns an ID for a hosted package named [name] at [version].
  ///
  /// If [url] is passed, it's the URL of the pub server from which the package
  /// should be downloaded. [url] most be normalized and validated using
  /// [validateAndNormalizeHostedUrl].
  PackageId idFor(String name, Version version, {Uri? url}) => PackageId(
      name, this, version, _HostedDescription(name, url ?? defaultUrl));

  /// Returns the description for a hosted package named [name] with the
  /// given package server [url].
  dynamic _serializedDescriptionFor(String name, [Uri? url]) {
    if (url == null) {
      return name;
    }
    try {
      url = validateAndNormalizeHostedUrl(url.toString());
    } on FormatException catch (e) {
      throw ArgumentError.value(url, 'url', 'url must be normalized: $e');
    }
    return {'name': name, 'url': url.toString()};
  }

  @override
  dynamic serializeDescription(String containingPath, description) {
    final desc = _asDescription(description);
    return _serializedDescriptionFor(desc.packageName, desc.uri);
  }

  @override
  String formatDescription(description) =>
      'on ${_asDescription(description).uri}';

  @override
  bool descriptionsEqual(description1, description2) =>
      _asDescription(description1) == _asDescription(description2);

  @override
  int hashDescription(description) => _asDescription(description).hashCode;

  /// Ensures that [description] is a valid hosted package description.
  ///
  /// Simple hosted dependencies only consist of a plain string, which is
  /// resolved against the default host. In this case, [description] will be
  /// null.
  ///
  /// Hosted dependencies may also specify a custom host from which the package
  /// is fetched. There are two syntactic forms of those dependencies:
  ///
  ///  1. With an url and an optional name in a map: `hosted: {url: <url>}`
  ///  2. With a direct url: `hosted: <url>`
  @override
  PackageRef parseRef(String name, description,
      {String? containingPath, required LanguageVersion languageVersion}) {
    return PackageRef(
        name, this, _parseDescription(name, description, languageVersion));
  }

  @override
  PackageId parseId(String name, Version version, description,
      {String? containingPath}) {
    // Old pub versions only wrote `description: <pkg>` into the lock file.
    if (description is String) {
      if (description != name) {
        throw FormatException('The description should be the same as the name');
      }
      return PackageId(
          name, this, version, _HostedDescription(name, defaultUrl));
    }

    final serializedDescription = (description as Map).cast<String, String>();

    return PackageId(
      name,
      this,
      version,
      _HostedDescription(serializedDescription['name']!,
          Uri.parse(serializedDescription['url']!)),
    );
  }

  _HostedDescription _asDescription(desc) => desc as _HostedDescription;

  /// Parses the description for a package.
  ///
  /// If the package parses correctly, this returns a (name, url) pair. If not,
  /// this throws a descriptive FormatException.
  _HostedDescription _parseDescription(
    String packageName,
    description,
    LanguageVersion languageVersion,
  ) {
    if (description == null) {
      // Simple dependency without a `hosted` block, use the default server.
      return _HostedDescription(packageName, defaultUrl);
    }

    final canUseShorthandSyntax =
        languageVersion >= _minVersionForShorterHostedSyntax;

    if (description is String) {
      // Old versions of pub (pre Dart 2.15) interpret `hosted: foo` as
      // `hosted: {name: foo, url: <default>}`.
      // For later versions, we treat it as `hosted: {name: <inferred>,
      // url: foo}` if a user opts in by raising their min SDK environment.
      //
      // Since the old behavior is very rarely used and we want to show a
      // helpful error message if the new syntax is used without raising the SDK
      // environment, we throw an error if something that looks like a URI is
      // used as a package name.
      if (canUseShorthandSyntax) {
        return _HostedDescription(
            packageName, validateAndNormalizeHostedUrl(description));
      } else {
        if (_looksLikePackageName.hasMatch(description)) {
          // Valid use of `hosted: package` dependency with an old SDK
          // environment.
          return _HostedDescription(description, defaultUrl);
        } else {
          throw FormatException(
            'Using `hosted: <url>` is only supported with a minimum SDK '
            'constraint of $_minVersionForShorterHostedSyntax.',
          );
        }
      }
    }

    if (description is! Map) {
      throw FormatException('The description must be a package name or map.');
    }

    var name = description['name'];
    if (canUseShorthandSyntax) name ??= packageName;

    if (name is! String) {
      throw FormatException("The 'name' key must have a string value without "
          'a minimum Dart SDK constraint of $_minVersionForShorterHostedSyntax.0 or higher.');
    }

    var url = defaultUrl;
    final u = description['url'];
    if (u != null) {
      if (u is! String) {
        throw FormatException("The 'url' key must be a string value.");
      }
      url = validateAndNormalizeHostedUrl(u);
    }

    return _HostedDescription(name, url);
  }

  /// Minimum language version at which short hosted syntax is supported.
  ///
  /// This allows `hosted` dependencies to be expressed as:
  /// ```yaml
  /// dependencies:
  ///   foo:
  ///     hosted: https://some-pub.com/path
  ///     version: ^1.0.0
  /// ```
  ///
  /// At older versions, `hosted` dependencies had to be a map with a `url` and
  /// a `name` key.
  static const LanguageVersion _minVersionForShorterHostedSyntax =
      LanguageVersion(2, 15);

  static final RegExp _looksLikePackageName =
      RegExp(r'^[a-zA-Z_]+[a-zA-Z0-9_]*$');
}

/// Information about a package version retrieved from /api/packages/$package
class _VersionInfo {
  final Pubspec pubspec;
  final Uri archiveUrl;
  final PackageStatus status;

  _VersionInfo(this.pubspec, this.archiveUrl, this.status);
}

/// The [PackageName.description] for a [HostedSource], storing the package name
/// and resolved URI of the package server.
class _HostedDescription {
  final String packageName;
  final Uri uri;

  _HostedDescription(this.packageName, this.uri) {
    ArgumentError.checkNotNull(packageName, 'packageName');
    ArgumentError.checkNotNull(uri, 'uri');
  }

  @override
  int get hashCode => Object.hash(packageName, uri);

  @override
  bool operator ==(Object other) {
    return other is _HostedDescription &&
        other.packageName == packageName &&
        other.uri == uri;
  }
}

/// The [BoundSource] for [HostedSource].
class BoundHostedSource extends CachedSource {
  @override
  final HostedSource source;

  @override
  final SystemCache systemCache;
  late RateLimitedScheduler<PackageRef, Map<PackageId, _VersionInfo>?>
      _scheduler;

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
                isDiscontinued: body['isDiscontinued'] ?? false,
                discontinuedReplacedBy: body['replacedBy'],
                isRetracted: map['retracted'] ?? false);
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

  Future<Map<PackageId, _VersionInfo>?> _fetchVersionsNoPrefetching(
      PackageRef ref) async {
    final serverUrl = _hostedUrl(ref.description);
    final url = _listVersionsUrl(ref.description);
    log.io('Get versions from $url.');

    late final String bodyText;
    late final dynamic body;
    late final Map<PackageId, _VersionInfo> result;
    try {
      // TODO(sigurdm): Implement cancellation of requests. This probably
      // requires resolution of: https://github.com/dart-lang/sdk/issues/22265.
      bodyText = await withAuthenticatedClient(
        systemCache,
        serverUrl,
        (client) => client.read(url, headers: pubApiHeaders),
      );
      final decoded = jsonDecode(bodyText);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('version listing must be a mapping');
      }
      body = decoded;
      result = _versionInfoFromPackageListing(body, ref, url);
    } on Exception catch (error, stackTrace) {
      var parsed = source._asDescription(ref.description);
      _throwFriendlyError(error, stackTrace, parsed.packageName, parsed.uri);
    }

    // Cache the response on disk.
    // Don't cache overly big responses.
    if (bodyText.length < 100 * 1024) {
      await _cacheVersionListingResponse(body, ref);
    }
    return result;
  }

  Future<Map<PackageId, _VersionInfo>?> _fetchVersions(PackageRef ref) async {
    final preschedule =
        Zone.current[_prefetchingKey] as void Function(PackageRef)?;

    /// Prefetch the dependencies of the latest version, we are likely to need
    /// them later.
    void prescheduleDependenciesOfLatest(
        Map<PackageId, _VersionInfo>? listing) {
      if (listing == null) return;
      final latestVersion =
          maxBy(listing.keys.map((id) => id.version), (e) => e)!;
      final latestVersionId =
          PackageId(ref.name, source, latestVersion, ref.description);
      final dependencies =
          listing[latestVersionId]?.pubspec.dependencies.values ?? [];
      unawaited(withDependencyType(DependencyType.none, () async {
        for (final packageRange in dependencies) {
          if (packageRange.source is HostedSource) {
            preschedule!(packageRange.toRef());
          }
        }
      }));
    }

    if (preschedule != null) {
      /// If we have a cached response - preschedule dependencies of that.
      prescheduleDependenciesOfLatest(
        await _cachedVersionListingResponse(ref),
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

  /// An in-memory cache to store the cached version listing loaded from
  /// [_versionListingCachePath].
  ///
  /// Invariant: Entries in this cache are the parsed version of the exact same
  ///  information cached on disk. I.e. if the entry is present in this cache,
  /// there will not be a newer version on disk.
  final Map<PackageRef, Pair<DateTime, Map<PackageId, _VersionInfo>>>
      _responseCache = {};

  /// If a cached version listing response for [ref] exists on disk and is less
  /// than [maxAge] old it is parsed and returned.
  ///
  /// Otherwise deletes a cached response if it exists and returns `null`.
  ///
  /// If [maxAge] is not given, we will try to get the cached version no matter
  /// how old it is.
  Future<Map<PackageId, _VersionInfo>?> _cachedVersionListingResponse(
      PackageRef ref,
      {Duration? maxAge}) async {
    if (_responseCache.containsKey(ref)) {
      final cacheAge = DateTime.now().difference(_responseCache[ref]!.first);
      if (maxAge == null || maxAge > cacheAge) {
        // The cached value is not too old.
        return _responseCache[ref]!.last;
      }
    }
    final cachePath = _versionListingCachePath(ref);
    final stat = io.File(cachePath).statSync();
    final now = DateTime.now();
    if (stat.type == io.FileSystemEntityType.file) {
      if (maxAge == null || now.difference(stat.modified) < maxAge) {
        try {
          final cachedDoc = jsonDecode(readTextFile(cachePath));
          final timestamp = cachedDoc['_fetchedAt'];
          if (timestamp is String) {
            final parsedTimestamp = DateTime.parse(timestamp);
            final cacheAge = DateTime.now().difference(parsedTimestamp);
            if (maxAge != null && cacheAge > maxAge) {
              // Too old according to internal timestamp - delete.
              tryDeleteEntry(cachePath);
            } else {
              var res = _versionInfoFromPackageListing(
                cachedDoc,
                ref,
                Uri.file(cachePath),
              );
              _responseCache[ref] = Pair(parsedTimestamp, res);
              return res;
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
  Future<void> _cacheVersionListingResponse(
      Map<String, dynamic> body, PackageRef ref) async {
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
      // Delete the entry in the in-memory cache to maintain the invariant that
      // cached information in memory is the same as that on the disk.
      _responseCache.remove(ref);
    } on io.IOException catch (e) {
      // Not being able to write this cache is not fatal. Just move on...
      log.fine('Failed writing cache file. $e');
    }
  }

  @override
  Future<PackageStatus> status(PackageId id, {Duration? maxAge}) async {
    final ref = id.toRef();
    // Did we already get info for this package?
    var versionListing = _scheduler.peek(ref);
    if (maxAge != null) {
      // Do we have a cached version response on disk?
      versionListing ??=
          await _cachedVersionListingResponse(ref, maxAge: maxAge);
    }
    // Otherwise retrieve the info from the host.
    versionListing ??= await _scheduler
        .schedule(ref)
        // Failures retrieving the listing here should just be ignored.
        .catchError(
          (_) => <PackageId, _VersionInfo>{},
          test: (error) => error is Exception,
        );

    final listing = versionListing![id];
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
    final parsed = source._asDescription(ref.description);
    final dir = _urlToDirectory(parsed.uri);
    // Use a dot-dir because older versions of pub won't choke on that
    // name when iterating the cache (it is not listed by [listDir]).
    return p.join(systemCacheRoot, dir, _versionListingDirectory,
        '${ref.name}-versions.json');
  }

  static const _versionListingDirectory = '.cache';

  /// Downloads a list of all versions of a package that are available from the
  /// site.
  @override
  Future<List<PackageId>> doGetVersions(
      PackageRef ref, Duration? maxAge) async {
    var versionListing = _scheduler.peek(ref);
    if (maxAge != null) {
      // Do we have a cached version response on disk?
      versionListing ??=
          await _cachedVersionListingResponse(ref, maxAge: maxAge);
    }
    versionListing ??= await _scheduler.schedule(ref);
    return versionListing!.keys.toList();
  }

  /// Parses [description] into its server and package name components, then
  /// converts that to a Uri for listing versions of the given package.
  Uri _listVersionsUrl(description) {
    final parsed = source._asDescription(description);
    final hostedUrl = parsed.uri;
    final package = Uri.encodeComponent(parsed.packageName);
    return hostedUrl.resolve('api/packages/$package');
  }

  /// Parses [description] into server name component.
  Uri _hostedUrl(description) {
    final parsed = source._asDescription(description);
    return parsed.uri;
  }

  /// Retrieves the pubspec for a specific version of a package that is
  /// available from the site.
  @override
  Future<Pubspec> describeUncached(PackageId id) async {
    final versions = await _scheduler.schedule(id.toRef());
    final url = _listVersionsUrl(id.description);
    return versions![id]?.pubspec ??
        (throw PackageNotFoundException('Could not find package $id at $url'));
  }

  /// Downloads the package identified by [id] to the system cache.
  @override
  Future<Package> downloadToSystemCache(PackageId id) async {
    if (!isInSystemCache(id)) {
      var packageDir = getDirectoryInCache(id);
      ensureDir(p.dirname(packageDir));
      await _download(id, packageDir);
    }

    return Package.load(id.name, getDirectoryInCache(id), systemCache.sources);
  }

  /// The system cache directory for the hosted source contains subdirectories
  /// for each separate repository URL that's used on the system.
  ///
  /// Each of these subdirectories then contains a subdirectory for each
  /// package downloaded from that site.
  @override
  String getDirectoryInCache(PackageId id) {
    var parsed = source._asDescription(id.description);
    var dir = _urlToDirectory(parsed.uri);
    return p.join(systemCacheRoot, dir, '${parsed.packageName}-${id.version}');
  }

  /// Re-downloads all packages that have been previously downloaded into the
  /// system cache from any server.
  @override
  Future<Iterable<RepairResult>> repairCachedPackages() async {
    if (!dirExists(systemCacheRoot)) return [];

    return (await Future.wait(listDir(systemCacheRoot).map((serverDir) async {
      final directory = p.basename(serverDir);
      Uri url;
      try {
        url = _directoryToUrl(directory);
      } on FormatException {
        log.error('Unable to detect hosted url from directory: $directory');
        // If _directoryToUrl can't intepret a directory name, we just silently
        // ignore it and hope it's because it comes from a newer version of pub.
        //
        // This is most likely because someone manually modified PUB_CACHE.
        return <RepairResult>[];
      }

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
                url: url,
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
          packages.map((package) async {
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
          }),
        ));
    })))
        .expand((x) => x);
  }

  /// Returns the best-guess package ID for [basename], which should be a
  /// subdirectory in a hosted cache.
  PackageId _idForBasename(String basename, {Uri? url}) {
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
        .whereNotNull()
        .toList();
  }

  /// Downloads package [package] at [version] from the archive_url and unpacks
  /// it into [destPath].
  ///
  /// If there is no archive_url, try to fetch it from
  /// `$server/packages/$package/versions/$version.tar.gz` where server comes
  /// from `id.description`.
  Future _download(PackageId id, String destPath) async {
    // We never want to use a cached `archive_url`, so we never attempt to load
    // the version listing from cache. Besides in most cases we already have
    // downloaded a fresh copy of the version listing response in the in-memory
    // cache, so looking in the file-system is pointless.
    //
    // We avoid using cached `archive_url` values because the `archive_url` for
    // a custom package server may include a temporary signature in the
    // query-string as is the case with signed S3 URLs. And we wish to allow for
    // such URLs to be used.
    final versions = await _scheduler.schedule(id.toRef());
    final versionInfo = versions![id];
    final packageName = id.name;
    final version = id.version;
    if (versionInfo == null) {
      throw PackageNotFoundException(
          'Package $packageName has no version $version');
    }
    final parsedDescription = source._asDescription(id.description);
    final server = parsedDescription.uri;

    var url = versionInfo.archiveUrl;
    log.io('Get package from $url.');
    log.message('Downloading ${log.bold(id.name)} ${id.version}...');

    // Download and extract the archive to a temp directory.
    await withTempDir((tempDirForArchive) async {
      var archivePath =
          p.join(tempDirForArchive, '$packageName-$version.tar.gz');
      var response = await withAuthenticatedClient(systemCache, server,
          (client) => client.send(http.Request('GET', url)));

      // We download the archive to disk instead of streaming it directly into
      // the tar unpacking. This simplifies stream handling.
      // Package:tar cancels the stream when it reaches end-of-archive, and
      // cancelling a http stream makes it not reusable.
      // There are ways around this, and we might revisit this later.
      await createFileFromStream(response.stream, archivePath);
      var tempDir = systemCache.createTempDir();
      await extractTarGz(readBinaryFileAsSream(archivePath), tempDir);

      // Remove the existing directory if it exists. This will happen if
      // we're forcing a download to repair the cache.
      if (dirExists(destPath)) deleteEntry(destPath);

      // Now that the get has succeeded, move it to the real location in the
      // cache. This ensures that we don't leave half-busted ghost
      // directories in the user's pub cache if a get fails.
      renameDir(tempDir, destPath);
    });
  }

  /// When an error occurs trying to read something about [package] from [url],
  /// this tries to translate into a more user friendly error message.
  ///
  /// Always throws an error, either the original one or a better one.
  Never _throwFriendlyError(
    error,
    StackTrace stackTrace,
    String package,
    Uri url,
  ) {
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
  String _urlToDirectory(Uri hostedUrl) {
    var url = hostedUrl.toString();
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
      url,
      RegExp(r'[<>:"\\/|?*%]'),
      (match) => '%${match[0]!.codeUnitAt(0)}',
    );
  }

  /// Given a directory name in the system cache, returns the URL of the server
  /// whose packages it contains.
  ///
  /// See [_urlToDirectory] for details on the mapping. Note that because the
  /// directory name does not preserve the scheme, this has to guess at it. It
  /// chooses "http" for loopback URLs (mainly to support the pub tests) and
  /// "https" for all others.
  Uri _directoryToUrl(String directory) {
    // Decode the pseudo-URL-encoded characters.
    var chars = '<>:"\\/|?*%';
    for (var i = 0; i < chars.length; i++) {
      var c = chars.substring(i, i + 1);
      directory = directory.replaceAll('%${c.codeUnitAt(0)}', c);
    }

    // If the URL has an explicit scheme, use that.
    if (directory.contains('://')) {
      return Uri.parse(directory);
    }

    // Otherwise, default to http for localhost and https for everything else.
    var scheme =
        isLoopback(directory.replaceAll(RegExp(':.*'), '')) ? 'http' : 'https';
    return Uri.parse('$scheme://$directory');
  }

  /// Returns the server URL for [description].
  Uri _serverFor(description) => source._asDescription(description).uri;

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
  Future<List<PackageId>> doGetVersions(
    PackageRef ref,
    Duration? maxAge,
  ) async {
    var parsed = source._asDescription(ref.description);
    var server = parsed.uri;
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
  Future<PackageStatus> status(PackageId id, {Duration? maxAge}) async {
    // Do we have a cached version response on disk?
    final versionListing = await _cachedVersionListingResponse(id.toRef());

    if (versionListing == null) {
      return PackageStatus();
    }
    // If we don't have the specific version we return the empty response.
    //
    // This should not happen. But in production we want to avoid a crash, since
    // it is more or less harmless.
    //
    // TODO(sigurdm): Consider representing the non-existence of the
    // package-version in the return value.
    return versionListing[id]?.status ?? PackageStatus();
  }
}
