// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

/// The current global [PackageServer].
PackageServer get globalPackageServer => _globalPackageServer;
PackageServer _globalPackageServer;

/// Creates an HTTP server that replicates the structure of pub.dartlang.org and
/// makes it the current [globalServer].
///
/// Calls [callback] with a [PackageServerBuilder] that's used to specify
/// which packages to serve.
Future servePackages(void Function(PackageServerBuilder) callback) async {
  _globalPackageServer = await PackageServer.start(callback);
  globalServer = _globalPackageServer._inner;

  addTearDown(() {
    _globalPackageServer = null;
  });
}

/// Like [servePackages], but instead creates an empty server with no packages
/// registered.
///
/// This will always replace a previous server.
Future serveNoPackages() => servePackages((_) {});

class PackageServer {
  /// The inner [DescriptorServer] that this uses to serve its descriptors.
  final DescriptorServer _inner;

  /// The [d.DirectoryDescriptor] describing the server layout of
  /// `/api/packages` on the test server.
  ///
  /// This contains metadata for packages that are being served via
  /// [servePackages].
  final _servedApiPackageDir = d.dir('packages', []);

  /// The [d.DirectoryDescriptor] describing the server layout of `/packages` on
  /// the test server.
  ///
  /// This contains the tarballs for packages that are being served via
  /// [servePackages].
  final _servedPackageDir = d.dir('packages', []);

  /// The current [PackageServerBuilder] that a user uses to specify which
  /// package to serve.
  ///
  /// This is preserved so that additional packages can be added.
  PackageServerBuilder _builder;

  /// The port used for the server.
  int get port => _inner.port;

  /// The URL for the server.
  String get url => 'http://localhost:$port';

  /// Creates an HTTP server that replicates the structure of pub.dartlang.org.
  ///
  /// Calls [callback] with a [PackageServerBuilder] that's used to specify
  /// which packages to serve.
  static Future<PackageServer> start(
      void Function(PackageServerBuilder) callback) async {
    var descriptorServer = await DescriptorServer.start();
    var server = PackageServer._(descriptorServer);
    descriptorServer.contents
      ..add(d.dir('api', [server._servedApiPackageDir]))
      ..add(server._servedPackageDir);
    server.add(callback);
    return server;
  }

  PackageServer._(this._inner) {
    _builder = PackageServerBuilder._(this);
  }

  /// Add to the current set of packages that are being served.
  void add(void Function(PackageServerBuilder) callback) {
    callback(_builder);

    _servedApiPackageDir.contents.clear();
    _servedPackageDir.contents.clear();

    _builder._packages.forEach((name, versions) {
      _servedApiPackageDir.contents.addAll([
        d.file(
            name,
            jsonEncode({
              'name': name,
              'uploaders': ['nweiz@google.com'],
              'versions': versions
                  .map((version) => packageVersionApiMap(url, version.pubspec))
                  .toList()
            })),
        d.dir(name, [
          d.dir('versions', versions.map((version) {
            return d.file(
                version.version.toString(),
                jsonEncode(
                    packageVersionApiMap(url, version.pubspec, full: true)));
          }))
        ])
      ]);

      _servedPackageDir.contents.add(d.dir(name, [
        d.dir(
            'versions',
            versions.map((version) =>
                d.tar('${version.version}.tar.gz', version.contents)))
      ]));
    });
  }

  /// Returns the path of [package] at [version], installed from this server, in
  /// the pub cache.
  String pathInCache(String package, String version) => p.join(
      d.sandbox, cachePath, 'hosted/localhost%58$port/$package-$version');

  /// Replace the current set of packages that are being served.
  void replace(void Function(PackageServerBuilder) callback) {
    _builder._clear();
    add(callback);
  }
}

/// A builder for specifying which packages should be served by [servePackages].
class PackageServerBuilder {
  /// A map from package names to a list of concrete packages to serve.
  final _packages = <String, List<_ServedPackage>>{};

  /// The package server that this builder is associated with.
  final PackageServer _server;

  /// The URL for the server that this builder is associated with.
  String get serverUrl => _server.url;

  PackageServerBuilder._(this._server);

  /// Specifies that a package named [name] with [version] should be served.
  ///
  /// If [deps] is passed, it's used as the "dependencies" field of the pubspec.
  /// If [pubspec] is passed, it's used as the rest of the pubspec.
  ///
  /// If [contents] is passed, it's used as the contents of the package. By
  /// default, a package just contains a dummy lib directory.
  void serve(String name, String version,
      {Map<String, dynamic> deps,
      Map<String, dynamic> pubspec,
      Iterable<d.Descriptor> contents}) {
    var pubspecFields = <String, dynamic>{'name': name, 'version': version};
    if (pubspec != null) pubspecFields.addAll(pubspec);
    if (deps != null) pubspecFields['dependencies'] = deps;

    contents ??= [d.libDir(name, '$name $version')];
    contents = [d.file('pubspec.yaml', yaml(pubspecFields)), ...contents];

    var packages = _packages.putIfAbsent(name, () => []);
    packages.add(_ServedPackage(pubspecFields, contents));
  }

  /// Clears all existing packages from this builder.
  void _clear() {
    _packages.clear();
  }
}

/// A package that's intended to be served.
class _ServedPackage {
  final Map pubspec;
  final List<d.Descriptor> contents;

  Version get version => Version.parse(pubspec['version']);

  _ServedPackage(this.pubspec, this.contents);
}
