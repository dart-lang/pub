// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub/src/third_party/tar/tar.dart';
import 'package:pub/src/utils.dart' show hexEncode;
import 'package:pub_semver/pub_semver.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:test/test.dart' as test show expect;

import 'descriptor.dart' as d;
import 'test_pub.dart';

class PackageServer {
  /// The inner [DescriptorServer] that this uses to serve its descriptors.
  final shelf.Server _inner;

  /// Handlers of requests. Last matching handler will be used.
  final List<_PatternAndHandler> _handlers = [];

  // A list of all the requests received up till now.
  final List<String> requestedPaths = <String>[];

  // Setting this to true will make automatic calculation of content-hashes.
  bool serveContentHashes = false;

  PackageServer._(this._inner) {
    _inner.mount((request) {
      final path = request.url.path;
      requestedPaths.add(path);

      final pathWithInitialSlash = '/$path';
      for (final entry in _handlers.reversed) {
        final match = entry.pattern.matchAsPrefix(pathWithInitialSlash);
        if (match != null && match.end == pathWithInitialSlash.length) {
          final a = entry.handler(request);
          return a;
        }
      }
      return shelf.Response.notFound('Could not find ${request.url}');
    });
  }

  static final _versionInfoPattern = RegExp(r'/api/packages/([a-zA-Z_0-9]*)');
  static final _downloadPattern =
      RegExp(r'/packages/([^/]*)/versions/([^/]*).tar.gz');

  static Future<PackageServer> start() async {
    final server =
        PackageServer._(await shelf_io.IOServer.bind('localhost', 0));
    server.handle(
      _versionInfoPattern,
      (shelf.Request request) async {
        final parts = request.url.pathSegments;
        assert(parts[0] == 'api');
        assert(parts[1] == 'packages');
        final name = parts[2];

        final package = server._packages[name];
        if (package == null) {
          return shelf.Response.notFound('No package named $name');
        }
        return shelf.Response.ok(jsonEncode({
          'name': name,
          'uploaders': ['nweiz@google.com'],
          'versions': [
            for (final version in package.versions.values)
              {
                'pubspec': version.pubspec,
                'version': version.version.toString(),
                'archive_url':
                    '${server.url}/packages/$name/versions/${version.version}.tar.gz',
                if (version.isRetracted) 'retracted': true,
                if (version.sha256 != null || server.serveContentHashes)
                  'archive_sha256': version.sha256 ??
                      hexEncode(
                          (await sha256.bind(version.contents()).first).bytes)
              }
          ],
          if (package.isDiscontinued) 'isDiscontinued': true,
          if (package.discontinuedReplacementText != null)
            'replacedBy': package.discontinuedReplacementText,
        }));
      },
    );

    server.handle(
      _downloadPattern,
      (shelf.Request request) {
        final parts = request.url.pathSegments;
        assert(parts[0] == 'packages');
        final name = parts[1];
        assert(parts[2] == 'versions');
        final package = server._packages[name];
        if (package == null) {
          return shelf.Response.notFound('No package $name');
        }

        final version = Version.parse(
            parts[3].substring(0, parts[3].length - '.tar.gz'.length));
        assert(parts[3].endsWith('.tar.gz'));

        for (final packageVersion in package.versions.values) {
          if (packageVersion.version == version) {
            return shelf.Response.ok(packageVersion.contents());
          }
        }
        return shelf.Response.notFound('No version $version of $name');
      },
    );
    return server;
  }

  Future<void> close() async {
    await _inner.close();
  }

  /// The port used for the server.
  int get port => _inner.url.port;

  /// The URL for the server.
  String get url => _inner.url.toString();

  /// From now on report errors on any request.
  void serveErrors() => _handlers
    ..clear()
    ..add(
      _PatternAndHandler(
        RegExp('.*'),
        (request) {
          fail('The HTTP server received an unexpected request:\n'
              '${request.method} ${request.requestedUri}');
        },
      ),
    );

  void handle(Pattern pattern, shelf.Handler handler) {
    _handlers.add(
      _PatternAndHandler(
        pattern,
        handler,
      ),
    );
  }

  // Installs a handler at [pattern] that expects to be called exactly once with
  // the given [method].
  //
  // The handler is installed as the start to give it priority over more general
  // handlers.
  void expect(String method, Pattern pattern, shelf.Handler handler) {
    handle(
      pattern,
      expectAsync1(
        (request) {
          test.expect(request.method, method);
          return handler(request);
        },
      ),
    );
  }

  /// Returns the path of [package] at [version], installed from this server, in
  /// the pub cache.
  String pathInCache(String package, String version) =>
      p.join(cachingPath, '$package-$version');

  /// The location where pub will store the cache for this server.
  String get cachingPath =>
      p.join(d.sandbox, cachePath, 'hosted', 'localhost%58$port');

  /// A map from package names to the concrete packages to serve.
  final _packages = <String, _ServedPackage>{};

  /// Specifies that a package named [name] with [version] should be served.
  ///
  /// If [deps] is passed, it's used as the "dependencies" field of the pubspec.
  /// If [pubspec] is passed, it's used as the rest of the pubspec.
  ///
  /// If [contents] is passed, it's used as the contents of the package. By
  /// default, a package just contains a dummy lib directory.
  void serve(String name, String version,
      {Map<String, dynamic>? deps,
      Map<String, dynamic>? pubspec,
      List<d.Descriptor>? contents}) {
    var pubspecFields = <String, dynamic>{'name': name, 'version': version};
    if (pubspec != null) pubspecFields.addAll(pubspec);
    if (deps != null) pubspecFields['dependencies'] = deps;

    contents ??= [d.libDir(name, '$name $version')];
    contents = [d.file('pubspec.yaml', yaml(pubspecFields)), ...contents];

    var package = _packages.putIfAbsent(name, _ServedPackage.new);
    package.versions[version] = _ServedPackageVersion(
      pubspecFields,
      contents: () {
        final entries = <TarEntry>[];

        void addDescriptor(d.Descriptor descriptor, String path) {
          if (descriptor is d.DirectoryDescriptor) {
            for (final e in descriptor.contents) {
              addDescriptor(e, p.posix.join(path, descriptor.name));
            }
          } else {
            entries.add(
              TarEntry(
                TarHeader(
                  // Ensure paths in tar files use forward slashes
                  name: p.posix.join(path, descriptor.name),
                  // We want to keep executable bits, but otherwise use the default
                  // file mode
                  mode: 420,
                  // size: 100,
                  modified: DateTime.fromMicrosecondsSinceEpoch(0),
                  userName: 'pub',
                  groupName: 'pub',
                ),
                (descriptor as d.FileDescriptor).readAsBytes(),
              ),
            );
          }
        }

        for (final e in contents ?? <d.Descriptor>[]) {
          addDescriptor(e, '');
        }
        return Stream.fromIterable(entries)
            .transform(tarWriterWith(format: OutputFormat.gnuLongName))
            .transform(gzip.encoder);
      },
    );
  }

  // Mark a package discontinued.
  void discontinue(String name,
      {bool isDiscontinued = true, String? replacementText}) {
    _packages[name]!
      ..isDiscontinued = isDiscontinued
      ..discontinuedReplacementText = replacementText;
  }

  /// Clears all existing packages from this builder.
  void clearPackages() {
    _packages.clear();
  }

  void retractPackageVersion(String name, String version) {
    _packages[name]!.versions[version]!.isRetracted = true;
  }

  /// Useful for testing handling of a wrong hash.
  void setSha256(String name, String version, String sha256) {
    _packages[name]!.versions[version]!.sha256 = sha256;
  }

  Future<String> getSha256(String name, String version) async {
    final v = _packages[name]!.versions[version]!;
    return v.sha256 ?? hexEncode((await sha256.bind(v.contents()).first).bytes);
  }
}

class _ServedPackage {
  final versions = <String, _ServedPackageVersion>{};
  bool isDiscontinued = false;
  String? discontinuedReplacementText;
}

/// A package that's intended to be served.
class _ServedPackageVersion {
  final Map pubspec;
  final Stream<List<int>> Function() contents;
  bool isRetracted = false;
  // Overrides the calculated sha256.
  String? sha256;

  Version get version => Version.parse(pubspec['version']);

  _ServedPackageVersion(this.pubspec, {required this.contents});
}

class _PatternAndHandler {
  Pattern pattern;
  shelf.Handler handler;

  _PatternAndHandler(this.pattern, this.handler);
}
