// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart'
    show IterableExtension, IterableNullableExtension, maxBy;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stack_trace/stack_trace.dart';

import '../authentication/client.dart';
import '../crc32c.dart';
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

const contentHashesDocumentationUrl = 'https://dart.dev/go/content-hashes';

/// Validates and normalizes a [hostedUrl] which is pointing to a pub server.
///
/// A [hostedUrl] is a URL pointing to a _hosted pub server_ as defined by the
/// [repository-spec-v2][1]. The default value is `pub.dev`, and can be
/// overwritten using `PUB_HOSTED_URL`. It can also specified for individual
/// hosted-dependencies in `pubspec.yaml`, and for the root package using the
/// `publish_to` key.
///
/// The [hostedUrl] is always normalized to a [Uri] with path that ends in slash
/// unless the path is merely `/`, in which case we normalize to the bare
/// domain.
///
/// We change `https://pub.dartlang.org` to `https://pub.dev`, this  maintains
/// backwards compatibility with `pubspec.lock`-files which contain
/// `https://pub.dartlang.org`.
///
/// Throws [FormatException] if there is anything wrong with [hostedUrl].
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
    u = u.replace(path: '${u.path}/');
  }
  // pub.dev and pub.dartlang.org are identical.
  //
  // We rewrite here to avoid caching both, and to avoid having different
  // credentials for these two.
  //
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
  if (u == Uri.parse('https://pub.dartlang.org')) {
    log.fine('Using https://pub.dev instead of https://pub.dartlang.org.');
    u = Uri.parse('https://pub.dev');
  }
  return u;
}

/// A package source that gets packages from a package hosting site that uses
/// the same API as pub.dev.
class HostedSource extends CachedSource {
  static HostedSource instance = HostedSource._();

  HostedSource._();

  @override
  final name = 'hosted';
  @override
  final hasMultipleVersions = true;

  static String pubDevUrl = 'https://pub.dev';
  static String pubDartlangUrl = 'https://pub.dartlang.org';

  static bool isPubDevUrl(String url) {
    final parsedUrl = Uri.parse(url);
    if (parsedUrl.scheme != 'http' && parsedUrl.scheme != 'https') {
      // A non http(s) url is not pub.dev.
      return false;
    }
    if (parsedUrl.host.isEmpty) {
      // The empty host is not pub.dev.
      return false;
    }
    final origin = parsedUrl.origin;
    // Allow the defaultHostedUrl to be overriden when running from tests
    if (runningFromTest &&
        io.Platform.environment['_PUB_TEST_DEFAULT_HOSTED_URL'] != null) {
      return origin == io.Platform.environment['_PUB_TEST_DEFAULT_HOSTED_URL'];
    }
    return origin == pubDevUrl || origin == pubDartlangUrl;
  }

  static bool isFromPubDev(PackageId id) {
    final description = id.description.description;
    return description is HostedDescription && isPubDevUrl(description.url);
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
      var defaultHostedUrl = 'https://pub.dev';
      // Allow the defaultHostedUrl to be overriden when running from tests
      if (runningFromTest) {
        defaultHostedUrl =
            io.Platform.environment['_PUB_TEST_DEFAULT_HOSTED_URL'] ??
                defaultHostedUrl;
      }
      return validateAndNormalizeHostedUrl(
        io.Platform.environment['PUB_HOSTED_URL'] ?? defaultHostedUrl,
      ).toString();
    } on FormatException catch (e) {
      throw ConfigException(
        'Invalid `PUB_HOSTED_URL="${e.source}"`: ${e.message}',
      );
    }
  }();

  /// Whether extra metadata headers should be sent for HTTP requests to a given
  /// [url].
  static bool shouldSendAdditionalMetadataFor(Uri url) {
    if (runningFromTest && Platform.environment.containsKey('PUB_HOSTED_URL')) {
      if (url.origin != Platform.environment['PUB_HOSTED_URL']) {
        return false;
      }
    } else {
      if (!HostedSource.isPubDevUrl(url.toString())) return false;
    }

    if (Platform.environment.containsKey('CI') &&
        Platform.environment['CI'] != 'false') {
      return false;
    }

    return true;
  }

  /// Returns a reference to a hosted package named [name].
  ///
  /// If [url] is passed, it's the URL of the pub server from which the package
  /// should be downloaded. [url] will be normalized and validated using
  /// [validateAndNormalizeHostedUrl]. This can throw a [FormatException].
  PackageRef refFor(String name, {String? url}) {
    final d = HostedDescription(name, url ?? defaultUrl);
    return PackageRef(name, d);
  }

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
  PackageRef parseRef(
    String name,
    description, {
    String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    return PackageRef(
      name,
      _parseDescription(name, description, languageVersion),
    );
  }

  @override
  PackageId parseId(
    String name,
    Version version,
    description, {
    String? containingDir,
  }) {
    // Old pub versions only wrote `description: <pkg>` into the lock file.
    if (description is String) {
      if (description != name) {
        throw FormatException('The description should be the same as the name');
      }
      return PackageId(
        name,
        version,
        ResolvedHostedDescription(
          HostedDescription(name, defaultUrl),
          sha256: null,
        ),
      );
    }
    if (description is! Map) {
      throw FormatException('The description should be a string or a map.');
    }
    final url = description['url'];
    if (url is! String) {
      throw FormatException('The url should be a string.');
    }
    final sha256 = description['sha256'];
    if (sha256 != null && sha256 is! String) {
      throw FormatException('The sha256 should be a string.');
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
        HostedDescription(name, url),
        sha256: _parseContentHash(sha256 as String?),
      ),
    );
  }

  /// Decodes a sha256 hash from a lock-file or package-listing.
  /// It is expected to be a hex-encoded String of length 64.
  ///
  /// Throws a [FormatException] if the string cannot be decoded.
  Uint8List? _parseContentHash(String? encoded) {
    if (encoded == null) return null;
    if (encoded.length != 64) {
      throw FormatException('Content-hash has incorrect length');
    }
    try {
      return hexDecode(encoded);
    } on FormatException catch (e) {
      return throw FormatException(
        'Badly formatted content-hash: ${e.message}',
      );
    }
  }

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
        return HostedDescription(packageName, description);
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

    final u = description['url'];
    if (u != null && u is! String) {
      throw FormatException("The 'url' key must be a string value.");
    }
    final url = u ?? defaultUrl;

    return HostedDescription(name, url as String);
  }

  static final RegExp _looksLikePackageName =
      RegExp(r'^[a-zA-Z_]+[a-zA-Z0-9_]*$');

  late final RateLimitedScheduler<_RefAndCache, List<_VersionInfo>> _scheduler =
      RateLimitedScheduler(
    _fetchVersions,
    maxConcurrentOperations: 10,
  );

  List<_VersionInfo> _versionInfoFromPackageListing(
    Map body,
    PackageRef ref,
    Uri location,
    SystemCache cache,
  ) {
    final description = ref.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final versions = body['versions'];
    if (versions is! List) {
      throw FormatException('versions must be a list');
    }
    return versions.map((map) {
      final pubspecData = map['pubspec'];
      if (pubspecData is! Map) {
        throw FormatException('pubspec must be a map');
      }
      var pubspec = Pubspec.fromMap(
        pubspecData,
        cache.sources,
        expectedName: ref.name,
        location: location,
      );
      final archiveSha256 = map['archive_sha256'];
      if (archiveSha256 != null && archiveSha256 is! String) {
        throw FormatException('archive_sha256 must be a String');
      }
      final archiveUrl = map['archive_url'];
      if (archiveUrl is! String) {
        throw FormatException('archive_url must be a String');
      }
      final status = PackageStatus(
        isDiscontinued: asBool(body['isDiscontinued']),
        discontinuedReplacedBy: body['replacedBy'] as String?,
        isRetracted: asBool(map['retracted']),
      );
      return _VersionInfo(
        pubspec.version,
        pubspec,
        Uri.parse(archiveUrl),
        status,
        _parseContentHash(archiveSha256 as String?),
      );
    }).toList();
  }

  Future<List<_VersionInfo>> _fetchVersionsNoPrefetching(
    PackageRef ref,
    SystemCache cache,
  ) async {
    final description = ref.description;

    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final packageName = description.packageName;
    final hostedUrl = description.url;
    final url = _listVersionsUrl(ref);
    log.io('Get versions from $url.');

    final String bodyText;
    final dynamic body;
    final List<_VersionInfo> result;
    try {
      // TODO(sigurdm): Implement cancellation of requests. This probably
      // requires resolution of: https://github.com/dart-lang/http/issues/424.
      bodyText = await withAuthenticatedClient(cache, Uri.parse(hostedUrl),
          (client) async {
        return await retryForHttp(
            'fetching versions for "$packageName" from "$url"', () async {
          final request = http.Request('GET', url);
          request.attachPubApiHeaders();
          request.attachMetadataHeaders();
          final response = await client.fetch(request);
          return response.body;
        });
      });
      final decoded = jsonDecode(bodyText);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('version listing must be a mapping');
      }
      body = decoded;
      result = _versionInfoFromPackageListing(
        body as Map<String, dynamic>,
        ref,
        url,
        cache,
      );
    } on Exception catch (error, stackTrace) {
      _throwFriendlyError(error, stackTrace, packageName, hostedUrl);
    }

    // Cache the response on disk.
    // Don't cache overly big responses.
    if (bodyText.length < 500 * 1024) {
      await _cacheVersionListingResponse(body, ref, cache);
    }
    return result;
  }

  Future<List<_VersionInfo>> _fetchVersions(_RefAndCache refAndCache) async {
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
      List<_VersionInfo>? listing,
      SystemCache cache,
    ) {
      if (listing == null || listing.isEmpty) return;
      final latestVersion =
          maxBy<_VersionInfo, Version>(listing, (e) => e.version)!;
      final dependencies = latestVersion.pubspec.dependencies.values;
      unawaited(
        withDependencyType(DependencyType.none, () async {
          for (final packageRange in dependencies) {
            if (packageRange.source is HostedSource) {
              preschedule!(_RefAndCache(packageRange.toRef(), cache));
            }
          }
        }),
      );
    }

    final cache = refAndCache.cache;
    if (preschedule != null) {
      /// If we have a cached response - preschedule dependencies of that.
      prescheduleDependenciesOfLatest(
        await _cachedVersionListingResponse(ref, cache),
        cache,
      );
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
  final Map<PackageRef, Pair<DateTime, List<_VersionInfo>>> _responseCache = {};

  /// If a cached version listing response for [ref] exists on disk and is less
  /// than [maxAge] old it is parsed and returned.
  ///
  /// Otherwise deletes a cached response if it exists and returns `null`.
  ///
  /// If [maxAge] is not given, we will try to get the cached version no matter
  /// how old it is.
  Future<List<_VersionInfo>?> _cachedVersionListingResponse(
    PackageRef ref,
    SystemCache cache, {
    Duration? maxAge,
  }) async {
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
          if (cachedDoc is! Map) {
            throw FormatException('Broken cached version listing response');
          }
          final timestamp = cachedDoc['_fetchedAt'];
          if (timestamp is! String) {
            throw FormatException('Broken cached version listing response');
          }
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
  Future<PackageStatus> status(
    PackageRef ref,
    Version version,
    SystemCache cache, {
    Duration? maxAge,
  }) async {
    // If we don't have the specific version we return the empty response, since
    // it is more or less harmless..
    //
    // This can happen if the connection is broken, or the server is faulty.
    // We want to avoid a crash
    //
    // TODO(sigurdm): Consider representing the non-existence of the
    // package-version in the return value.
    return (await _versionInfo(ref, version, cache, maxAge: maxAge))?.status ??
        PackageStatus();
  }

  Future<_VersionInfo?> _versionInfo(
    PackageRef ref,
    Version version,
    SystemCache cache, {
    Duration? maxAge,
  }) async {
    if (cache.isOffline) {
      // Do we have a cached version response on disk?
      final versionListing = await _cachedVersionListingResponse(ref, cache);

      if (versionListing == null) {
        return null;
      }
      return versionListing.firstWhereOrNull((l) => l.version == version);
    }
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
          (_) async => <_VersionInfo>[],
          test: (error) => error is Exception,
        );

    return versionListing.firstWhereOrNull((l) => l.version == version);
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
    return p.join(
      cache.rootDirForSource(this),
      dir,
      _versionListingDirectory,
      '${ref.name}-versions.json',
    );
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
    return versionListing
        .map(
          (i) => PackageId(
            ref.name,
            i.version,
            ResolvedHostedDescription(
              ref.description as HostedDescription,
              sha256: i.archiveSha256,
            ),
          ),
        )
        .toList();
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
    return versions.firstWhereOrNull((i) => i.version == id.version)?.pubspec ??
        (throw PackageNotFoundException('Could not find package $id at $url'));
  }

  /// Downloads the package identified by [id] to the system cache if needed.
  ///
  /// Validates that the content hash of [id] corresponds to what is already in
  /// cache, if not the file is redownloaded.
  ///
  /// If [allowOutdatedHashChecks] is `true` we use a cached version listing
  /// response if present instead of probing the server. Not probing allows for
  /// `pub get` with a filled cache to be a fast case that doesn't require any
  /// new version-listings.
  @override
  Future<DownloadPackageResult> downloadToSystemCache(
    PackageId id,
    SystemCache cache,
  ) async {
    var didUpdate = false;
    final packageDir = getDirectoryInCache(id, cache);

    // Use the content-hash from the version-info to compare with what we
    // already downloaded.
    //
    // The content-hash from [id] will be compared with that when the lockfile
    // is written.
    //
    // We allow the version-listing to be a few days outdated in order for `pub
    // get` with an existing working resolution and everything in cache to be
    // fast.
    final versionInfo = await _versionInfo(
      id.toRef(),
      id.version,
      cache,
      maxAge: Duration(days: 3),
    );

    final expectedContentHash = versionInfo?.archiveSha256 ??
        // Handling of legacy server - we use the hash from the id (typically
        // from the lockfile) to compare to the existing download.
        (id.description as ResolvedHostedDescription).sha256;
    Uint8List? contentHash;
    if (!fileExists(hashPath(id, cache))) {
      if (dirExists(packageDir) && !cache.isOffline) {
        log.fine(
          'Cache entry for ${id.name}-${id.version} has no content-hash - redownloading.',
        );
        deleteEntry(packageDir);
      }
    } else if (expectedContentHash == null) {
      // Can happen with a legacy server combined with a legacy lock file.
      log.fine(
        'Content-hash of ${id.name}-${id.version} not known from resolution.',
      );
    } else {
      final hashFromCache = sha256FromCache(id, cache);
      if (!fixedTimeBytesEquals(hashFromCache, expectedContentHash)) {
        log.warning(
          'Cached version of ${id.name}-${id.version} has wrong hash - redownloading.',
        );
        if (cache.isOffline) {
          fail('Cannot redownload while offline. Try again without --offline.');
        }
        deleteEntry(packageDir);
      } else {
        contentHash = hashFromCache;
      }
    }
    if (dirExists(packageDir)) {
      contentHash ??= sha256FromCache(id, cache);
    } else {
      didUpdate = true;
      if (cache.isOffline) {
        fail(
          'Missing package ${id.name}-${id.version}. Try again without --offline.',
        );
      }
      contentHash = await _download(id, packageDir, cache);
    }
    return DownloadPackageResult(
      PackageId(
        id.name,
        id.version,
        (id.description as ResolvedHostedDescription).withSha256(contentHash),
      ),
      didUpdate: didUpdate,
    );
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

  /// The system cache directory for the hosted source contains subdirectories
  /// for each separate repository URL that's used on the system.
  ///
  /// Parallel to this there is a `hosted-hashes` directory with a stored hash
  /// of all downloaded packages.
  String hashPath(PackageId id, SystemCache cache) {
    final description = id.description.description;
    if (description is! HostedDescription) {
      throw ArgumentError('Wrong source');
    }
    final rootDir = cache.rootDir;

    var serverDir = _urlToDirectory(description.url);
    return p.join(
      rootDir,
      'hosted-hashes',
      serverDir,
      '${id.name}-${id.version}.sha256',
    );
  }

  /// Loads the hash at `hashPath(id)`.
  Uint8List? sha256FromCache(PackageId id, SystemCache cache) {
    try {
      return _parseContentHash(readTextFile(hashPath(id, cache)));
    } on io.IOException {
      return null;
    } on FormatException catch (e) {
      log.fine('Bad content-hash in cache: $e, ignoring cache entry');
      return null;
    }
  }

  /// Re-downloads all packages that have been previously downloaded into the
  /// system cache from any server.
  @override
  Future<Iterable<RepairResult>> repairCachedPackages(SystemCache cache) async {
    final rootDir = cache.rootDirForSource(this);
    if (!dirExists(rootDir)) return [];

    return (await Future.wait(
      listDir(rootDir).map((serverDir) async {
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
          ..addAll(
            await Future.wait(
              packages.map((package) async {
                var id = PackageId(
                  package.name,
                  package.version,
                  ResolvedHostedDescription(
                    HostedDescription._(package.name, url),
                    sha256: null,
                  ),
                );
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
                  return RepairResult(
                    id.name,
                    id.version,
                    this,
                    success: false,
                  );
                }
              }),
            ),
          );
      }),
    ))
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
      ResolvedHostedDescription(HostedDescription(name, url), sha256: null),
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
  ///
  /// Returns the content-hash of the downloaded archive.
  Future<Uint8List> _download(
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
    final versionInfo =
        versions.firstWhereOrNull((i) => i.version == id.version);
    final packageName = id.name;
    final version = id.version;
    late final Uint8List contentHash;
    if (versionInfo == null) {
      throw PackageNotFoundException(
        'Package $packageName has no version $version',
      );
    }

    final archiveUrl = versionInfo.archiveUrl;
    log.io('Get package from $archiveUrl.');
    log.fine('Downloading ${log.bold(id.name)} ${id.version}...');

    // Download and extract the archive to a temp directory.
    return await withTempDir((tempDirForArchive) async {
      var fileName = '$packageName-$version.tar.gz';
      var archivePath = p.join(tempDirForArchive, fileName);

      Stream<List<int>> validateSha256(
        Stream<List<int>> stream,
        Digest? expectedHash,
      ) async* {
        final output = _SingleValueSink<Digest>();
        final input = sha256.startChunkedConversion(output);
        await for (final v in stream) {
          input.add(v);
          yield v;
        }
        input.close();
        final actualHash = output.value;
        if (expectedHash != null && output.value != expectedHash) {
          log.fine(
            'Expected content-hash for ${id.name}-${id.version} $expectedHash actual: ${output.value}.',
          );
          throw PackageIntegrityException('''
Downloaded archive for ${id.name}-${id.version} had wrong content-hash.

This indicates a problem on the package repository: `${description.url}`.

See $contentHashesDocumentationUrl.
''');
        }
        contentHash = Uint8List.fromList(actualHash.bytes);
        writeHash(id, cache, contentHash);
      }

      // It is important that we do not compare against id.description.sha256,
      // as we need to check against the newly fetched version listing to ensure
      // that content changes result in updated lockfiles, not failure to
      // download.
      final expectedSha256 = versionInfo.archiveSha256;

      try {
        await withAuthenticatedClient(cache, Uri.parse(description.url),
            (client) async {
          // In addition to HTTP errors, this will retry crc32c/sha256 errors as
          // well because [PackageIntegrityException] subclasses
          // [PubHttpException].
          await retryForHttp('downloading "$archiveUrl"', () async {
            final request = http.Request('GET', archiveUrl);
            request.attachMetadataHeaders();
            final response = await client.fetchAsStream(request);

            Stream<List<int>> stream = response.stream;
            final expectedCrc32c = _parseCrc32c(response.headers, fileName);
            if (expectedCrc32c != null) {
              stream = _validateCrc32c(
                response.stream,
                expectedCrc32c,
                id,
                archiveUrl,
              );
            }
            stream = validateSha256(
              stream,
              (expectedSha256 == null) ? null : Digest(expectedSha256),
            );

            // We download the archive to disk instead of streaming it directly
            // into the tar unpacking. This simplifies stream handling.
            // Package:tar cancels the stream when it reaches end-of-archive, and
            // cancelling a http stream makes it not reusable.
            // There are ways around this, and we might revisit this later.
            await createFileFromStream(stream, archivePath);
          });
        });
      } on Exception catch (error, stackTrace) {
        _throwFriendlyError(error, stackTrace, id.name, description.url);
      }

      var tempDir = cache.createTempDir();
      try {
        try {
          await extractTarGz(readBinaryFileAsStream(archivePath), tempDir);
        } on FormatException catch (e) {
          dataError('Failed to extract `$archivePath`: ${e.message}.');
        }
        ensureDir(p.dirname(destPath));
      } catch (e) {
        deleteEntry(tempDir);
        rethrow;
      }
      // Now that the get has succeeded, move it to the real location in the
      // cache.
      //
      // If this fails with a "directory not empty" exception we assume that
      // another pub process has installed the same package version while we
      // downloaded.
      tryRenameDir(tempDir, destPath);
      return contentHash;
    });
  }

  /// Writes the contenthash for [id] in the cache.
  void writeHash(PackageId id, SystemCache cache, List<int> bytes) {
    final path = hashPath(id, cache);
    ensureDir(p.dirname(path));
    writeTextFile(
      path,
      hexEncode(bytes),
    );
  }

  /// Installs a tar.gz file in [archivePath] as if it was downloaded from a
  /// package repository.
  ///
  /// The name, version and repository are decided from the pubspec.yaml that
  /// must be present in the archive.
  Future<PackageId> preloadPackage(
    String archivePath,
    SystemCache cache,
  ) async {
    // Extract to a temp-folder and do atomic rename to preserve the integrity
    // of the cache.
    late final Uint8List contentHash;

    var tempDir = cache.createTempDir();
    final PackageId id;
    try {
      try {
        // We read the file twice, once to compute the hash, and once to extract
        // the archive.
        //
        // It would be desirable to read the file only once, but the tar
        // extraction closes the stream early making things tricky to get right.
        contentHash = Uint8List.fromList(
          (await sha256.bind(readBinaryFileAsStream(archivePath)).first).bytes,
        );
        await extractTarGz(readBinaryFileAsStream(archivePath), tempDir);
      } on FormatException catch (e) {
        dataError('Failed to extract `$archivePath`: ${e.message}.');
      }
      if (!fileExists(p.join(tempDir, 'pubspec.yaml'))) {
        fail(
          'Found no `pubspec.yaml` in $archivePath. Is it a valid pub package archive?',
        );
      }
      final Pubspec pubspec;
      try {
        pubspec = Pubspec.load(tempDir, cache.sources);
        final errors = pubspec.allErrors;
        if (errors.isNotEmpty) {
          throw errors.first;
        }
      } on Exception catch (e) {
        fail('Failed to load `pubspec.yaml` from `$archivePath`: $e.');
      }
      // Reconstruct the PackageId from the extracted pubspec.yaml.
      id = PackageId(
        pubspec.name,
        pubspec.version,
        ResolvedHostedDescription(
          HostedDescription(pubspec.name, defaultUrl),
          sha256: contentHash,
        ),
      );
    } catch (e) {
      deleteEntry(tempDir);
      rethrow;
    }
    final packageDir = getDirectoryInCache(id, cache);
    if (dirExists(packageDir)) {
      log.fine(
        'Cache entry for ${id.name}-${id.version} already exists. Replacing.',
      );
      deleteEntry(packageDir);
    }
    tryRenameDir(tempDir, packageDir);
    writeHash(id, cache, contentHash);
    return id;
  }

  /// When an error occurs trying to read something about [package] from [hostedUrl],
  /// this tries to translate into a more user friendly error message.
  ///
  /// Always throws an error, either the original one or a better one.
  static Never _throwFriendlyError(
    Exception error,
    StackTrace stackTrace,
    String package,
    String hostedUrl,
  ) {
    if (error is PubHttpResponseException) {
      if (error.response.statusCode == 404) {
        throw PackageNotFoundException(
          'could not find package $package at $hostedUrl',
          innerError: error,
          innerTrace: stackTrace,
        );
      }

      fail(
        '${error.response.statusCode} ${error.response.reasonPhrase} trying '
        'to find package $package at $hostedUrl.',
        error,
        stackTrace,
      );
    } else if (error is io.SocketException) {
      fail(
        'Got socket error trying to find package $package at $hostedUrl.',
        error,
        stackTrace,
      );
    } else if (error is io.TlsException) {
      fail(
        'Got TLS error trying to find package $package at $hostedUrl.',
        error,
        stackTrace,
      );
    } else if (error is AuthenticationException) {
      String? hint;
      var message = 'authentication failed';

      assert(error.statusCode == 401 || error.statusCode == 403);
      if (error.statusCode == 401) {
        hint = '$hostedUrl package repository requested authentication!\n'
            'You can provide credentials using:\n'
            '    dart pub token add $hostedUrl';
      }
      if (error.statusCode == 403) {
        hint = 'Insufficient permissions to the resource at the $hostedUrl '
            'package repository.\nYou can modify credentials using:\n'
            '    dart pub token add $hostedUrl';
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
      return await runZoned(
        callback,
        zoneValues: {_prefetchingKey: preschedule},
      );
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

  HostedDescription._(this.packageName, this.url);

  // This can be used to construct a description with any specific url.
  factory HostedDescription.raw(String packageName, String url) =>
      HostedDescription._(packageName, url);

  factory HostedDescription(String packageName, String url) =>
      HostedDescription._(
        packageName,
        validateAndNormalizeHostedUrl(url).toString(),
      );

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
    if (languageVersion >=
        LanguageVersion.firstVersionWithShorterHostedSyntax) {
      return url;
    }
    return {'url': url, 'name': packageName};
  }

  @override
  HostedSource get source => HostedSource.instance;
}

class ResolvedHostedDescription extends ResolvedDescription {
  @override
  HostedDescription get description => super.description as HostedDescription;

  /// The content hash of the package archive (the `tar.gz` file) of the
  /// PackageId described by this.
  ///
  /// This can be obtained in several ways:
  /// * Reported from a server in the archive_sha256 field.
  ///   (will be null if the server does not report this.)
  /// * Obtained from a pubspec.lock
  ///   (will be null for legacy lock-files).
  /// * Read from the <PUB_CACHE>/hosted-hashes/<server>/<package>-<version>.sha256 file.
  ///   (will be null if the file doesn't exist for corrupt or legacy caches).
  final Uint8List? sha256;

  ResolvedHostedDescription(
    HostedDescription description, {
    required this.sha256,
  }) : super(description);

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    final hash = sha256;
    return {
      'name': description.packageName,
      'url': description.url,
      if (hash != null) 'sha256': hexEncode(hash),
    };
  }

  @override
  // We do not include the sha256 in the hashCode because of the equality
  // semantics.
  int get hashCode => description.hashCode;

  @override
  bool operator ==(Object other) {
    return other is ResolvedHostedDescription &&
        other.description == description &&
        // A [sha256] of `null` means that we don't know the hash yet.
        // Therefore we have to assume it is equal to any known value.
        (sha256 == null ||
            other.sha256 == null ||
            fixedTimeBytesEquals(sha256, other.sha256));
  }

  ResolvedHostedDescription withSha256(Uint8List? newSha256) =>
      ResolvedHostedDescription(description, sha256: newSha256);
}

/// Information about a package version retrieved from /api/packages/$package<
class _VersionInfo {
  final Pubspec pubspec;
  final Uri archiveUrl;
  final Version version;

  /// The sha256 digest of the archive according to the package-repository.
  final Uint8List? archiveSha256;
  final PackageStatus status;

  _VersionInfo(
    this.version,
    this.pubspec,
    this.archiveUrl,
    this.status,
    this.archiveSha256,
  );
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

/// A sink that can only have `add` called once, and that can retrieve the
/// value.
class _SingleValueSink<T> implements Sink<T> {
  late final T value;

  @override
  void add(T data) {
    value = data;
  }

  @override
  void close() {}
}

@visibleForTesting
const checksumHeaderName = 'x-goog-hash';

/// Adds a checksum validation "tap" to the response stream and returns a
/// wrapped `Stream` object, which should be used to consume the incoming data.
///
/// As chunks are received, a CRC32C checksum is updated.
/// Once the download is completed, the final checksum is compared with
/// the one present in the checksum response header.
///
/// Throws [PackageIntegrityException] if there is a checksum mismatch.
Stream<List<int>> _validateCrc32c(
  Stream<List<int>> stream,
  int expectedChecksum,
  PackageId id,
  Uri archiveUrl,
) async* {
  final crc32c = Crc32c();

  await for (final chunk in stream) {
    crc32c.update(chunk);
    yield chunk;
  }

  final actualChecksum = crc32c.finalize();

  log.fine(
      'Computed checksum $actualChecksum for ${id.name} ${id.version} with '
      'expected CRC32C of $expectedChecksum.');

  if (actualChecksum != expectedChecksum) {
    throw PackageIntegrityException(
        'Package archive for ${id.name} ${id.version} downloaded from '
        '"$archiveUrl" has "x-goog-hash: crc32c=$expectedChecksum", which '
        'doesn\'t match the checksum of the archive downloaded.');
  }
}

/// Parses response [headers] and returns the archive's CRC32C checksum.
///
/// In most cases, GCS provides both MD5 and CRC32C checksums in its response
/// headers. It uses the header name "x-goog-hash" for these values. It has
/// been documented and observed that GCS will send multiple response headers
/// with the same "x-goog-hash" token as the key.
/// https://cloud.google.com/storage/docs/xml-api/reference-headers#xgooghash
///
/// Additionally, when the Dart http client encounters multiple response
/// headers with the same key, it concatenates their values with a comma
/// before inserting a single item with that key and concatenated value into
/// its response "headers" Map.
/// See https://github.com/dart-lang/http/issues/24
/// https://github.com/dart-lang/http/blob/06649afbb5847dbb0293816ba8348766b116e419/pkgs/http/lib/src/base_response.dart#L29
///
/// Throws [PackageIntegrityException] if the CRC32C checksum cannot be parsed.
int? _parseCrc32c(Map<String, String> headers, String fileName) {
  final checksumHeader = headers[checksumHeaderName];
  if (checksumHeader == null) return null;

  final parts = checksumHeader.split(',');
  for (final part in parts) {
    if (part.startsWith('crc32c=')) {
      final undecoded = part.substring('crc32c='.length);

      try {
        final bytes = base64Decode(undecoded);

        // CRC32C must be 32 bits, or 4 bytes.
        if (bytes.length != 4) {
          throw FormatException('CRC32C checksum has invalid length', bytes);
        }

        return ByteData.view(bytes.buffer).getUint32(0);
      } on FormatException catch (e, s) {
        log.exception(e, s);
        throw PackageIntegrityException(
            'Package archive "$fileName" has a malformed CRC32C checksum in '
            'its response headers');
      }
    }
  }

  return null;
}
