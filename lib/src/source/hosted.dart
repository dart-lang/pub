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
class HostedSource extends CachedSource {
  static HostedSource instance = HostedSource._();

  HostedSource._();

  @override
  final name = 'hosted';
  @override
  final hasMultipleVersions = true;

  static String pubDevUrl = 'https://pub.dartlang.org';

  static bool isFromPubDev(PackageId id) {
    final description = id.description.description;
    return description is HostedDescription && description.url == pubDevUrl;
  }

  /// Gets the default URL for the package server for hosted dependencies.
  late final String defaultUrl = () {
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
      return validateAndNormalizeHostedUrl(
        io.Platform.environment['PUB_HOSTED_URL'] ?? 'https://pub.dartlang.org',
      ).toString();
    } on FormatException catch (e) {
      throw ConfigException(
          'Invalid `PUB_HOSTED_URL="${e.source}"`: ${e.message}');
    }
  }();

  /// Returns a reference to a hosted package named [name].
  ///
  /// If [url] is passed, it's the URL of the pub server from which the package
  /// should be downloaded. [url] most be normalized and validated using
  /// [validateAndNormalizeHostedUrl].
  PackageRef refFor(String name, {String? url}) {
    final d = HostedDescription(name, url ?? defaultUrl);
    return PackageRef(name, d);
  }

  /// Returns an ID for a hosted package named [name] at [version].
  ///
  /// If [url] is passed, it's the URL of the pub server from which the package
  /// should be downloaded. [url] most be normalized and validated using
  /// [validateAndNormalizeHostedUrl].
  PackageId idFor(
    String name,
    Version version, {
    String? url,
  }) =>
      PackageId(
        name,
        version,
        ResolvedHostedDescription(
          HostedDescription(name, url ?? defaultUrl.toString()),
        ),
      );

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
      {String? containingDir, required LanguageVersion languageVersion}) {
    return PackageRef(
        name, _parseDescription(name, description, languageVersion));
  }

  @override
  PackageId parseId(String name, Version version, description,
      {String? containingDir}) {
    // Old pub versions only wrote `description: <pkg>` into the lock file.
    if (description is String) {
      if (description != name) {
        throw FormatException('The description should be the same as the name');
      }
      return PackageId(
        name,
        version,
        ResolvedHostedDescription(HostedDescription(name, defaultUrl)),
      );
    }
    if (description is! Map) {
      throw FormatException('The description should be a string or a map.');
    }
    final url = description['url'];
    if (url is! String) {
      throw FormatException('The url should be a string.');
    }
    final foundName = description['name'];
    if (foundName is! String) {
      throw FormatException('The name should be a string.');
    }
    if (foundName != name) {
      throw FormatException('The name should be $name');
    }
    return PackageId(
      name,
      version,
      ResolvedHostedDescription(
        HostedDescription(name, Uri.parse(url).toString()),
      ),
    );
  }

  HostedDescription _asDescription(desc) => desc as HostedDescription;

  /// Parses the description for a package.
  ///
  /// If the package parses correctly, this returns a (name, url) pair. If not,
  /// this throws a descriptive FormatException.
  HostedDescription _parseDescription(
    String packageName,
    description,
    LanguageVersion languageVersion,
  ) {
    if (description == null) {
      // Simple dependency without a `hosted` block, use the default server.
      return HostedDescription(packageName, defaultUrl);
    }

    final canUseShorthandSyntax = languageVersion.supportsShorterHostedSyntax;

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
        return HostedDescription(
            packageName, validateAndNormalizeHostedUrl(description).toString());
      } else {
        if (_looksLikePackageName.hasMatch(description)) {
          // Valid use of `hosted: package` dependency with an old SDK
          // environment.
          return HostedDescription(description, defaultUrl);
        } else {
          throw FormatException(
            'Using `hosted: <url>` is only supported with a minimum SDK '
            'constraint of ${LanguageVersion.firstVersionWithShorterHostedSyntax}.',
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
          'a minimum Dart SDK constraint of ${LanguageVersion.firstVersionWithShorterHostedSyntax}.0 or higher.');
    }

    var url = defaultUrl;
    final u = description['url'];
    if (u != null) {
      if (u is! String) {
        throw FormatException("The 'url' key must be a string value.");
      }
      url = validateAndNormalizeHostedUrl(u).toString();
    }

    return HostedDescription(name, url);
  }

  static final RegExp _looksLikePackageName =
      RegExp(r'^[a-zA-Z_]+[a-zA-Z0-9_]*$');

  late final RateLimitedScheduler<_RefAndCache, Map<PackageId, _VersionInfo>?>
      _scheduler = RateLimitedScheduler(
    _fetchVersions,
    maxConcurrentOperations: 10,
  );

  Map<PackageId, _VersionInfo> _versionInfoFromPackageListing(
      Map body, PackageRef ref, Uri location, SystemCache cache) {
    final description = ref.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final versions = body['versions'];
    if (versions is List) {
      return Map.fromEntries(versions.map((map) {
        final pubspecData = map['pubspec'];
        if (pubspecData is Map) {
          var pubspec = Pubspec.fromMap(pubspecData, cache.sources,
              expectedName: ref.name, location: location);
          var id = idFor(
            ref.name,
            pubspec.version,
            url: description.url,
          );
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
      PackageRef ref, SystemCache cache) async {
    final description = ref.description;

    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final hostedUrl = description.url;
    final url = _listVersionsUrl(ref);
    log.io('Get versions from $url.');

    late final String bodyText;
    late final dynamic body;
    late final Map<PackageId, _VersionInfo> result;
    try {
      // TODO(sigurdm): Implement cancellation of requests. This probably
      // requires resolution of: https://github.com/dart-lang/sdk/issues/22265.
      bodyText = await withAuthenticatedClient(
        cache,
        Uri.parse(hostedUrl),
        (client) => client.read(url, headers: pubApiHeaders),
      );
      final decoded = jsonDecode(bodyText);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('version listing must be a mapping');
      }
      body = decoded;
      result = _versionInfoFromPackageListing(body, ref, url, cache);
    } on Exception catch (error, stackTrace) {
      final packageName = _asDescription(ref.description).packageName;
      _throwFriendlyError(error, stackTrace, packageName, hostedUrl);
    }

    // Cache the response on disk.
    // Don't cache overly big responses.
    if (bodyText.length < 100 * 1024) {
      await _cacheVersionListingResponse(body, ref, cache);
    }
    return result;
  }

  Future<Map<PackageId, _VersionInfo>?> _fetchVersions(
      _RefAndCache refAndCache) async {
    final ref = refAndCache.ref;
    final description = ref.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final preschedule =
        Zone.current[_prefetchingKey] as void Function(_RefAndCache)?;

    /// Prefetch the dependencies of the latest version, we are likely to need
    /// them later.
    void prescheduleDependenciesOfLatest(
      Map<PackageId, _VersionInfo>? listing,
      SystemCache cache,
    ) {
      if (listing == null) return;
      final latestVersion =
          maxBy(listing.keys.map((id) => id.version), (e) => e)!;
      final latestVersionId = PackageId(
          ref.name, latestVersion, ResolvedHostedDescription(description));
      final dependencies =
          listing[latestVersionId]?.pubspec.dependencies.values ?? [];
      unawaited(withDependencyType(DependencyType.none, () async {
        for (final packageRange in dependencies) {
          if (packageRange.source is HostedSource) {
            preschedule!(_RefAndCache(packageRange.toRef(), cache));
          }
        }
      }));
    }

    final cache = refAndCache.cache;
    if (preschedule != null) {
      /// If we have a cached response - preschedule dependencies of that.
      prescheduleDependenciesOfLatest(
          await _cachedVersionListingResponse(ref, cache), cache);
    }
    final result = await _fetchVersionsNoPrefetching(ref, cache);

    if (preschedule != null) {
      // Preschedule the dependencies from the actual response.
      // This might overlap with those from the cached response. But the
      // scheduler ensures each listing will be fetched at most once.
      prescheduleDependenciesOfLatest(result, cache);
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
      PackageRef ref, SystemCache cache,
      {Duration? maxAge}) async {
    if (_responseCache.containsKey(ref)) {
      final cacheAge = DateTime.now().difference(_responseCache[ref]!.first);
      if (maxAge == null || maxAge > cacheAge) {
        // The cached value is not too old.
        return _responseCache[ref]!.last;
      }
    }
    final cachePath = _versionListingCachePath(ref, cache);
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
                cache,
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
    Map<String, dynamic> body,
    PackageRef ref,
    SystemCache cache,
  ) async {
    final path = _versionListingCachePath(ref, cache);
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
  Future<PackageStatus> status(PackageId id, SystemCache cache,
      {Duration? maxAge}) async {
    if (cache.isOffline) {
      // Do we have a cached version response on disk?
      final versionListing =
          await _cachedVersionListingResponse(id.toRef(), cache);

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
    final ref = id.toRef();
    // Did we already get info for this package?
    var versionListing = _scheduler.peek(_RefAndCache(ref, cache));
    if (maxAge != null) {
      // Do we have a cached version response on disk?
      versionListing ??=
          await _cachedVersionListingResponse(ref, cache, maxAge: maxAge);
    }
    // Otherwise retrieve the info from the host.
    versionListing ??= await _scheduler
        .schedule(_RefAndCache(ref, cache))
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
  String _versionListingCachePath(PackageRef ref, SystemCache cache) {
    final description = ref.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final dir = _urlToDirectory(description.url);
    // Use a dot-dir because older versions of pub won't choke on that
    // name when iterating the cache (it is not listed by [listDir]).
    return p.join(cache.rootDirForSource(this), dir, _versionListingDirectory,
        '${ref.name}-versions.json');
  }

  static const _versionListingDirectory = '.cache';

  /// Downloads a list of all versions of a package that are available from the
  /// site.
  @override
  Future<List<PackageId>> doGetVersions(
    PackageRef ref,
    Duration? maxAge,
    SystemCache cache,
  ) async {
    final description = ref.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    if (cache.isOffline) {
      final url = description.url;
      final root = cache.rootDirForSource(HostedSource.instance);
      final dir = p.join(root, _urlToDirectory(url));
      log.io('Finding versions of ${ref.name} in $dir');
      List<PackageId> offlineVersions;
      if (dirExists(dir)) {
        offlineVersions = listDir(dir)
            .where(_looksLikePackageDir)
            .map((entry) => _idForBasename(p.basename(entry), url))
            .where((id) => id.name == ref.name && id.version != Version.none)
            .toList();
      } else {
        offlineVersions = [];
      }

      // If there are no versions in the cache, report a clearer error.
      if (offlineVersions.isEmpty) {
        throw PackageNotFoundException(
          'could not find package ${ref.name} in cache',
          hint: 'Try again without --offline!',
        );
      }

      return offlineVersions;
    }
    var versionListing = _scheduler.peek(_RefAndCache(ref, cache));
    if (maxAge != null) {
      // Do we have a cached version response on disk?
      versionListing ??=
          await _cachedVersionListingResponse(ref, cache, maxAge: maxAge);
    }
    versionListing ??= await _scheduler.schedule(_RefAndCache(ref, cache));
    return versionListing!.keys.toList();
  }

  /// Parses [description] into its server and package name components, then
  /// converts that to a Uri for listing versions of the given package.
  Uri _listVersionsUrl(PackageRef ref) {
    final description = ref.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final package = Uri.encodeComponent(ref.name);
    return Uri.parse(description.url).resolve('api/packages/$package');
  }

  /// Retrieves the pubspec for a specific version of a package that is
  /// available from the site.
  @override
  Future<Pubspec> describeUncached(PackageId id, SystemCache cache) async {
    if (cache.isOffline) {
      throw PackageNotFoundException(
        '${id.name} ${id.version} is not available in cache',
        hint: 'Try again without --offline!',
      );
    }
    final versions = await _scheduler.schedule(_RefAndCache(id.toRef(), cache));
    final url = _listVersionsUrl(id.toRef());
    return versions![id]?.pubspec ??
        (throw PackageNotFoundException('Could not find package $id at $url'));
  }

  /// Downloads the package identified by [id] to the system cache.
  @override
  Future<Package> downloadToSystemCache(PackageId id, SystemCache cache) async {
    if (!isInSystemCache(id, cache)) {
      if (cache.isOffline) {
        throw StateError('Cannot download packages when offline.');
      }
      var packageDir = getDirectoryInCache(id, cache);
      ensureDir(p.dirname(packageDir));
      await _download(id, packageDir, cache);
    }

    return Package.load(id.name, getDirectoryInCache(id, cache), cache.sources);
  }

  /// The system cache directory for the hosted source contains subdirectories
  /// for each separate repository URL that's used on the system.
  ///
  /// Each of these subdirectories then contains a subdirectory for each
  /// package downloaded from that site.
  @override
  String getDirectoryInCache(PackageId id, SystemCache cache) {
    final description = id.description.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final rootDir = cache.rootDirForSource(this);

    var dir = _urlToDirectory(description.url);
    return p.join(rootDir, dir, '${id.name}-${id.version}');
  }

  /// Re-downloads all packages that have been previously downloaded into the
  /// system cache from any server.
  @override
  Future<Iterable<RepairResult>> repairCachedPackages(SystemCache cache) async {
    final rootDir = cache.rootDirForSource(this);
    if (!dirExists(rootDir)) return [];

    return (await Future.wait(listDir(rootDir).map((serverDir) async {
      final directory = p.basename(serverDir);
      late final String url;
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
          packages.add(Package.load(null, entry, cache.sources));
        } catch (error, stackTrace) {
          log.error('Failed to load package', error, stackTrace);
          final id = _idForBasename(
            p.basename(entry),
            url,
          );
          results.add(
            RepairResult(
              id.name,
              id.version,
              this,
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
            var id = idFor(package.name, package.version, url: url);
            try {
              deleteEntry(package.dir);
              await _download(id, package.dir, cache);
              return RepairResult(id.name, id.version, this, success: true);
            } catch (error, stackTrace) {
              var message = 'Failed to repair ${log.bold(package.name)} '
                  '${package.version}';
              if (url != defaultUrl) message += ' from $url';
              log.error('$message. Error:\n$error');
              log.fine(stackTrace);

              tryDeleteEntry(package.dir);
              return RepairResult(id.name, id.version, this, success: false);
            }
          }),
        ));
    })))
        .expand((x) => x);
  }

  /// Returns the best-guess package ID for [basename], which should be a
  /// subdirectory in a hosted cache.
  PackageId _idForBasename(String basename, String url) {
    var components = split1(basename, '-');
    var version = Version.none;
    if (components.length > 1) {
      try {
        version = Version.parse(components.last);
      } on FormatException {
        // Default to Version.none.
      }
    }
    final name = components.first;
    return PackageId(
      name,
      version,
      ResolvedHostedDescription(HostedDescription(name, url)),
    );
  }

  bool _looksLikePackageDir(String path) {
    var components = split1(p.basename(path), '-');
    if (components.length < 2) return false;
    try {
      Version.parse(components.last);
    } on FormatException {
      return false;
    }
    return dirExists(path);
  }

  /// Gets all of the packages that have been downloaded into the system cache
  /// from the default server.
  @override
  List<Package> getCachedPackages(SystemCache cache) {
    final root = cache.rootDirForSource(HostedSource.instance);
    var cacheDir =
        p.join(root, _urlToDirectory(HostedSource.instance.defaultUrl));
    if (!dirExists(cacheDir)) return [];

    return listDir(cacheDir)
        .where(_looksLikePackageDir)
        .map((entry) {
          try {
            return Package.load(null, entry, cache.sources);
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
  Future _download(
    PackageId id,
    String destPath,
    SystemCache cache,
  ) async {
    final description = id.description.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    // We never want to use a cached `archive_url`, so we never attempt to load
    // the version listing from cache. Besides in most cases we already have
    // downloaded a fresh copy of the version listing response in the in-memory
    // cache, so looking in the file-system is pointless.
    //
    // We avoid using cached `archive_url` values because the `archive_url` for
    // a custom package server may include a temporary signature in the
    // query-string as is the case with signed S3 URLs. And we wish to allow for
    // such URLs to be used.
    final versions = await _scheduler.schedule(_RefAndCache(id.toRef(), cache));
    final versionInfo = versions![id];
    final packageName = id.name;
    final version = id.version;
    if (versionInfo == null) {
      throw PackageNotFoundException(
          'Package $packageName has no version $version');
    }

    var url = versionInfo.archiveUrl;
    log.io('Get package from $url.');
    log.message('Downloading ${log.bold(id.name)} ${id.version}...');

    // Download and extract the archive to a temp directory.
    await withTempDir((tempDirForArchive) async {
      var archivePath =
          p.join(tempDirForArchive, '$packageName-$version.tar.gz');
      var response = await withAuthenticatedClient(
          cache,
          Uri.parse(description.url),
          (client) => client.send(http.Request('GET', url)));

      // We download the archive to disk instead of streaming it directly into
      // the tar unpacking. This simplifies stream handling.
      // Package:tar cancels the stream when it reaches end-of-archive, and
      // cancelling a http stream makes it not reusable.
      // There are ways around this, and we might revisit this later.
      await createFileFromStream(response.stream, archivePath);
      var tempDir = cache.createTempDir();
      await extractTarGz(readBinaryFileAsSream(archivePath), tempDir);

      // Now that the get has succeeded, move it to the real location in the
      // cache.
      //
      // If this fails with a "directory not empty" exception we assume that
      // another pub process has installed the same package version while we
      // downloaded.
      tryRenameDir(tempDir, destPath);
    });
  }

  /// When an error occurs trying to read something about [package] from [hostedUrl],
  /// this tries to translate into a more user friendly error message.
  ///
  /// Always throws an error, either the original one or a better one.
  Never _throwFriendlyError(
    Exception error,
    StackTrace stackTrace,
    String package,
    String hostedUrl,
  ) {
    if (error is PubHttpException) {
      if (error.response.statusCode == 404) {
        throw PackageNotFoundException(
            'could not find package $package at $hostedUrl',
            innerError: error,
            innerTrace: stackTrace);
      }

      fail(
          '${error.response.statusCode} ${error.response.reasonPhrase} trying '
          'to find package $package at $hostedUrl.',
          error,
          stackTrace);
    } else if (error is io.SocketException) {
      fail('Got socket error trying to find package $package at $hostedUrl.',
          error, stackTrace);
    } else if (error is io.TlsException) {
      fail('Got TLS error trying to find package $package at $hostedUrl.',
          error, stackTrace);
    } else if (error is AuthenticationException) {
      String? hint;
      var message = 'authentication failed';

      assert(error.statusCode == 401 || error.statusCode == 403);
      if (error.statusCode == 401) {
        hint = '$hostedUrl package repository requested authentication!\n'
            'You can provide credentials using:\n'
            '    pub token add $hostedUrl';
      }
      if (error.statusCode == 403) {
        hint = 'Insufficient permissions to the resource at the $hostedUrl '
            'package repository.\nYou can modify credentials using:\n'
            '    pub token add $hostedUrl';
        message = 'authorization failed';
      }

      if (error.serverMessage?.isNotEmpty == true && hint != null) {
        hint += '\n${error.serverMessage}';
      }

      throw PackageNotFoundException(message, hint: hint);
    } else if (error is FormatException) {
      throw PackageNotFoundException(
        'Got badly formatted response trying to find package $package at $hostedUrl',
        innerError: error,
        innerTrace: stackTrace,
        hint: 'Check that "$hostedUrl" is a valid package repository.',
      );
    } else {
      // Otherwise re-throw the original exception.
      throw error;
    }
  }

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

/// The [PackageName.description] for a [HostedSource], storing the package name
/// and resolved URI of the package server.
class HostedDescription extends Description {
  final String packageName;
  final String url;

  HostedDescription(this.packageName, this.url);

  @override
  int get hashCode => Object.hash(packageName, url);

  @override
  bool operator ==(Object other) {
    return other is HostedDescription &&
        other.packageName == packageName &&
        other.url == url;
  }

  @override
  String format() => 'on $url';

  @override
  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    if (url == source.defaultUrl) {
      return null;
    }
    return {'url': url, 'name': packageName};
  }

  @override
  HostedSource get source => HostedSource.instance;
}

class ResolvedHostedDescription extends ResolvedDescription {
  @override
  HostedDescription get description => super.description as HostedDescription;

  ResolvedHostedDescription(HostedDescription description) : super(description);

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    late final String url;
    try {
      url = validateAndNormalizeHostedUrl(description.url).toString();
    } on FormatException catch (e) {
      throw ArgumentError.value(url, 'url', 'url must be normalized: $e');
    }
    return {'name': description.packageName, 'url': url.toString()};
  }

  @override
  int get hashCode => description.hashCode;

  @override
  bool operator ==(Object other) {
    return other is ResolvedHostedDescription &&
        other.description == description;
  }
}

/// Information about a package version retrieved from /api/packages/$package<
class _VersionInfo {
  final Pubspec pubspec;
  final Uri archiveUrl;
  final PackageStatus status;

  _VersionInfo(this.pubspec, this.archiveUrl, this.status);
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
String _urlToDirectory(String hostedUrl) {
  // Normalize all loopback URLs to "localhost".
  final url = hostedUrl.replaceAllMapped(
      RegExp(r'^(https?://)(127\.0\.0\.1|\[::1\]|localhost)?'), (match) {
    // Don't include the scheme for HTTPS URLs. This makes the directory names
    // nice for the default and most recommended scheme. We also don't include
    // it for localhost URLs, since they're always known to be HTTP.
    var localhost = match[2] == null ? '' : 'localhost';
    var scheme = match[1] == 'https://' || localhost.isNotEmpty ? '' : match[1];
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
String _directoryToUrl(String directory) {
  // Decode the pseudo-URL-encoded characters.
  var chars = '<>:"\\/|?*%';
  for (var i = 0; i < chars.length; i++) {
    var c = chars.substring(i, i + 1);
    directory = directory.replaceAll('%${c.codeUnitAt(0)}', c);
  }

  // If the URL has an explicit scheme, use that.
  if (directory.contains('://')) {
    return Uri.parse(directory).toString();
  }

  // Otherwise, default to http for localhost and https for everything else.
  var scheme =
      isLoopback(directory.replaceAll(RegExp(':.*'), '')) ? 'http' : 'https';
  return Uri.parse('$scheme://$directory').toString();
}

// TODO(sigurdm): This is quite inelegant.
class _RefAndCache {
  final PackageRef ref;
  final SystemCache cache;
  _RefAndCache(this.ref, this.cache);

  @override
  int get hashCode => ref.hashCode;
  @override
  bool operator ==(Object other) => other is _RefAndCache && other.ref == ref;
}
