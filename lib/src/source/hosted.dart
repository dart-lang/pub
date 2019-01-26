// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import "dart:convert";
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:stack_trace/stack_trace.dart';

import '../exceptions.dart';
import '../http.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'cached.dart';

/// A package source that gets packages from a package hosting site that uses
/// the same API as pub.dartlang.org.
class HostedSource extends Source {
  final name = "hosted";
  final hasMultipleVersions = true;

  BoundHostedSource bind(SystemCache systemCache, {bool isOffline = false}) =>
      isOffline
          ? _OfflineHostedSource(this, systemCache)
          : BoundHostedSource(this, systemCache);

  /// Gets the default URL for the package server for hosted dependencies.
  String get defaultUrl =>
      _defaultUrl ??= _pubHostedUrlConfig() ?? 'https://pub.dartlang.org';
  String _defaultUrl;
  String _pubHostedUrlConfig() {
    var url = io.Platform.environment['PUB_HOSTED_URL'];
    if (url == null) return null;
    var uri = Uri.parse(url);
    if (uri.scheme?.isEmpty ?? true) {
      throw ConfigException(
          '`PUB_HOSTED_URL` must include a scheme such as "https://". '
          '$url is invalid');
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
  _descriptionFor(String name, [url]) {
    if (url == null) return name;

    if (url is! String && url is! Uri) {
      throw ArgumentError.value(url, 'url', 'must be a Uri or a String.');
    }

    return {'name': name, 'url': url.toString()};
  }

  String formatDescription(description) =>
      "on ${_parseDescription(description).last}";

  bool descriptionsEqual(description1, description2) =>
      _parseDescription(description1) == _parseDescription(description2);

  int hashDescription(description) => _parseDescription.hashCode;

  /// Ensures that [description] is a valid hosted package description.
  ///
  /// There are two valid formats. A plain string refers to a package with the
  /// given name from the default host, while a map with keys "name" and "url"
  /// refers to a package with the given name from the host at the given URL.
  PackageRef parseRef(String name, description, {String containingPath}) {
    _parseDescription(description);
    return PackageRef(name, this, description);
  }

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
      throw FormatException("The description must be a package name or map.");
    }

    if (!description.containsKey("name")) {
      throw FormatException("The description map must contain a 'name' key.");
    }

    var name = description["name"];
    if (name is! String) {
      throw FormatException("The 'name' key must have a string value.");
    }

    return Pair<String, String>(name, description["url"] ?? defaultUrl);
  }
}

/// The [BoundSource] for [HostedSource].
class BoundHostedSource extends CachedSource {
  final HostedSource source;

  final SystemCache systemCache;

  BoundHostedSource(this.source, this.systemCache);

  /// Downloads a list of all versions of a package that are available from the
  /// site.
  Future<List<PackageId>> doGetVersions(PackageRef ref) async {
    var url = _makeUrl(
        ref.description, (server, package) => "$server/api/packages/$package");

    log.io("Get versions from $url.");

    String body;
    try {
      body = await httpClient.read(url, headers: pubApiHeaders);
    } catch (error, stackTrace) {
      var parsed = source._parseDescription(ref.description);
      _throwFriendlyError(error, stackTrace, parsed.first, parsed.last);
    }

    var doc = jsonDecode(body);
    return (doc['versions'] as List).map((map) {
      var pubspec = Pubspec.fromMap(map['pubspec'], systemCache.sources,
          expectedName: ref.name, location: url);
      var id = source.idFor(ref.name, pubspec.version,
          url: _serverFor(ref.description));
      memoizePubspec(id, pubspec);

      return id;
    }).toList();
  }

  /// Parses [description] into its server and package name components, then
  /// converts that to a Uri given [pattern].
  ///
  /// Ensures the package name is properly URL encoded.
  Uri _makeUrl(description, String pattern(String server, String package)) {
    var parsed = source._parseDescription(description);
    var server = parsed.last;
    var package = Uri.encodeComponent(parsed.first);
    return Uri.parse(pattern(server, package));
  }

  /// Downloads and parses the pubspec for a specific version of a package that
  /// is available from the site.
  Future<Pubspec> describeUncached(PackageId id) async {
    // Request it from the server.
    var url = _makeVersionUrl(
        id,
        (server, package, version) =>
            "$server/api/packages/$package/versions/$version");

    log.io("Describe package at $url.");
    Map<String, dynamic> version;
    try {
      version = jsonDecode(await httpClient.read(url, headers: pubApiHeaders));
    } catch (error, stackTrace) {
      var parsed = source._parseDescription(id.description);
      _throwFriendlyError(error, stackTrace, id.name, parsed.last);
    }

    return Pubspec.fromMap(version['pubspec'], systemCache.sources,
        expectedName: id.name, location: url);
  }

  /// Downloads the package identified by [id] to the system cache.
  Future<Package> downloadToSystemCache(PackageId id) async {
    if (!isInSystemCache(id)) {
      var packageDir = getDirectory(id);
      ensureDir(p.dirname(packageDir));
      var parsed = source._parseDescription(id.description);
      await _download(parsed.last, parsed.first, id.version, packageDir);
    }

    return Package.load(id.name, getDirectory(id), systemCache.sources);
  }

  /// The system cache directory for the hosted source contains subdirectories
  /// for each separate repository URL that's used on the system.
  ///
  /// Each of these subdirectories then contains a subdirectory for each
  /// package downloaded from that site.
  String getDirectory(PackageId id) {
    var parsed = source._parseDescription(id.description);
    var dir = _urlToDirectory(parsed.last);
    return p.join(systemCacheRoot, dir, "${parsed.first}-${id.version}");
  }

  /// Re-downloads all packages that have been previously downloaded into the
  /// system cache from any server.
  Future<Pair<List<PackageId>, List<PackageId>>> repairCachedPackages() async {
    if (!dirExists(systemCacheRoot)) return Pair([], []);

    var successes = <PackageId>[];
    var failures = <PackageId>[];

    for (var serverDir in listDir(systemCacheRoot)) {
      var url = _directoryToUrl(p.basename(serverDir));

      var packages = <Package>[];
      for (var entry in listDir(serverDir)) {
        try {
          packages.add(Package.load(null, entry, systemCache.sources));
        } catch (error, stackTrace) {
          log.error("Failed to load package", error, stackTrace);
          failures.add(_idForBasename(p.basename(entry)));
          tryDeleteEntry(entry);
        }
      }

      packages.sort(Package.orderByNameAndVersion);

      for (var package in packages) {
        var id = source.idFor(package.name, package.version, url: url);

        try {
          await _download(url, package.name, package.version, package.dir);
          successes.add(id);
        } catch (error, stackTrace) {
          failures.add(id);
          var message = "Failed to repair ${log.bold(package.name)} "
              "${package.version}";
          if (url != source.defaultUrl) message += " from $url";
          log.error("$message. Error:\n$error");
          log.fine(stackTrace);

          tryDeleteEntry(package.dir);
        }
      }
    }

    return Pair(successes, failures);
  }

  /// Returns the best-guess package ID for [basename], which should be a
  /// subdirectory in a hosted cache.
  PackageId _idForBasename(String basename) {
    var components = split1(basename, '-');
    var version = Version.none;
    if (components.length > 1) {
      try {
        version = Version.parse(components.last);
      } catch (_) {
        // Default to Version.none.
      }
    }
    return PackageId(components.first, source, version, components.first);
  }

  /// Gets all of the packages that have been downloaded into the system cache
  /// from the default server.
  List<Package> getCachedPackages() {
    var cacheDir = p.join(systemCacheRoot, _urlToDirectory(source.defaultUrl));
    if (!dirExists(cacheDir)) return [];

    return listDir(cacheDir).map((entry) {
      try {
        return Package.load(null, entry, systemCache.sources);
      } catch (error, stackTrace) {
        log.fine("Failed to load package from $entry:\n"
            "$error\n"
            "${Chain.forTrace(stackTrace)}");
      }
    }).toList();
  }

  /// Downloads package [package] at [version] from [server], and unpacks it
  /// into [destPath].
  Future _download(
      String server, String package, Version version, String destPath) async {
    var url = Uri.parse("$server/packages/$package/versions/$version.tar.gz");
    log.io("Get package from $url.");
    log.message('Downloading ${log.bold(package)} $version...');

    // Download and extract the archive to a temp directory.
    var tempDir = systemCache.createTempDir();
    var response = await httpClient.send(http.Request("GET", url));
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
            "could not find package $package at $url",
            innerError: error,
            innerTrace: stackTrace);
      }

      fail(
          "${error.response.statusCode} ${error.response.reasonPhrase} trying "
          "to find package $package at $url.",
          error,
          stackTrace);
    } else if (error is io.SocketException) {
      fail("Got socket error trying to find package $package at $url.", error,
          stackTrace);
    } else if (error is io.TlsException) {
      fail("Got TLS error trying to find package $package at $url.", error,
          stackTrace);
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
        RegExp(r"^(https?://)(127\.0\.0\.1|\[::1\]|localhost)?"), (match) {
      // Don't include the scheme for HTTPS URLs. This makes the directory names
      // nice for the default and most recommended scheme. We also don't include
      // it for localhost URLs, since they're always known to be HTTP.
      var localhost = match[2] == null ? '' : 'localhost';
      var scheme =
          match[1] == 'https://' || localhost.isNotEmpty ? '' : match[1];
      return "$scheme$localhost";
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
      url = url.replaceAll("%${c.codeUnitAt(0)}", c);
    }

    // If the URL has an explicit scheme, use that.
    if (url.contains("://")) return url;

    // Otherwise, default to http for localhost and https for everything else.
    var scheme =
        isLoopback(url.replaceAll(RegExp(":.*"), "")) ? "http" : "https";
    return "$scheme://$url";
  }

  /// Returns the server URL for [description].
  Uri _serverFor(description) =>
      Uri.parse(source._parseDescription(description).last);

  /// Parses [id] into its server, package name, and version components, then
  /// converts that to a Uri given [pattern].
  ///
  /// Ensures the package name is properly URL encoded.
  Uri _makeVersionUrl(PackageId id,
      String pattern(String server, String package, String version)) {
    var parsed = source._parseDescription(id.description);
    var server = parsed.last;
    var package = Uri.encodeComponent(parsed.first);
    var version = Uri.encodeComponent(id.version.toString());
    return Uri.parse(pattern(server, package, version));
  }
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
  Future<List<PackageId>> doGetVersions(PackageRef ref) async {
    var parsed = source._parseDescription(ref.description);
    var server = parsed.last;
    log.io("Finding versions of ${ref.name} in "
        "$systemCacheRoot/${_urlToDirectory(server)}");

    var dir = p.join(systemCacheRoot, _urlToDirectory(server));

    List<PackageId> versions;
    if (dirExists(dir)) {
      versions = listDir(dir)
          .map((entry) {
            var components = p.basename(entry).split("-");
            if (components.first != ref.name) return null;
            return source.idFor(
                ref.name, Version.parse(components.skip(1).join("-")),
                url: _serverFor(ref.description));
          })
          .where((id) => id != null)
          .toList();
    } else {
      versions = [];
    }

    // If there are no versions in the cache, report a clearer error.
    if (versions.isEmpty) {
      throw PackageNotFoundException(
          "could not find package ${ref.name} in cache");
    }

    return versions;
  }

  Future _download(
      String server, String package, Version version, String destPath) {
    // Since HostedSource is cached, this will only be called for uncached
    // packages.
    throw UnsupportedError("Cannot download packages when offline.");
  }

  Future<Pubspec> describeUncached(PackageId id) {
    throw PackageNotFoundException(
        "${id.name} ${id.version} is not available in your system cache");
  }
}
