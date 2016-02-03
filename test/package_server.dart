// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:pub/src/utils.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scheduled_test/scheduled_test.dart';
import 'package:yaml/yaml.dart';

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
void servePackages(void callback(PackageServerBuilder builder)) {
  _globalPackageServer = new PackageServer(callback);
  globalServer = _globalPackageServer._inner;

  currentSchedule.onComplete.schedule(() {
    _globalPackageServer = null;
  }, 'clearing the global package server');
}

/// Like [servePackages], but instead creates an empty server with no packages
/// registered.
///
/// This will always replace a previous server.
void serveNoPackages() => servePackages((_) {});

/// A shortcut for [servePackages] that serves the version of barback used by
/// pub.
void serveBarback() {
  servePackages((builder) {
    builder.serveRealPackage('barback');
  });
}

class PackageServer {
  /// The inner [DescriptorServer] that this uses to serve its descriptors.
  DescriptorServer _inner;

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
  var _builder = new PackageServerBuilder._();

  /// A future that will complete to the port used for the server.
  Future<int> get port => _inner.port;

  /// Creates an HTTP server that replicates the structure of pub.dartlang.org.
  ///
  /// Calls [callback] with a [PackageServerBuilder] that's used to specify
  /// which packages to serve.
  PackageServer(void callback(PackageServerBuilder builder)) {
    _inner = new DescriptorServer([
      d.dir('api', [_servedApiPackageDir]),
      _servedPackageDir
    ]);

    add(callback);
  }

  /// Add to the current set of packages that are being served.
  void add(void callback(PackageServerBuilder builder)) {
    schedule(() async {
      callback(_builder);

      await _builder._await();
      _servedApiPackageDir.contents.clear();
      _servedPackageDir.contents.clear();

      _builder._packages.forEach((name, versions) {
        _servedApiPackageDir.contents.addAll([
          d.file('$name', JSON.encode({
            'name': name,
            'uploaders': ['nweiz@google.com'],
            'versions': versions.map((version) =>
                packageVersionApiMap(version.pubspec)).toList()
          })),
          d.dir(name, [
            d.dir('versions', versions.map((version) {
              return d.file(version.version.toString(), JSON.encode(
                  packageVersionApiMap(version.pubspec, full: true)));
            }))
          ])
        ]);

        _servedPackageDir.contents.add(d.dir(name, [
          d.dir('versions', versions.map((version) =>
              d.tar('${version.version}.tar.gz', version.contents)))
        ]));
      });
    }, 'adding packages to the package server');
  }

  /// Replace the current set of packages that are being served.
  void replace(void callback(PackageServerBuilder builder)) {
    schedule(() => _builder._clear(), "clearing builder");
    add(callback);
  }
}

/// A builder for specifying which packages should be served by [servePackages].
class PackageServerBuilder {
  /// A map from package names to a list of concrete packages to serve.
  final _packages = new Map<String, List<_ServedPackage>>();

  /// A group of futures from [serve] calls.
  ///
  /// This should be accessed by calling [_awair].
  var _futures = new FutureGroup();

  PackageServerBuilder._();

  /// Specifies that a package named [name] with [version] should be served.
  ///
  /// If [deps] is passed, it's used as the "dependencies" field of the pubspec.
  /// If [pubspec] is passed, it's used as the rest of the pubspec. Either of
  /// these may recursively contain Futures.
  ///
  /// If [contents] is passed, it's used as the contents of the package. By
  /// default, a package just contains a dummy lib directory.
  void serve(String name, String version, {Map deps, Map pubspec,
      Iterable<d.Descriptor> contents}) {
    _futures.add(Future.wait([
      awaitObject(deps),
      awaitObject(pubspec)
    ]).then((pair) {
      var resolvedDeps = pair.first;
      var resolvedPubspec = pair.last;

      var pubspecFields = {
        "name": name,
        "version": version
      };
      if (resolvedPubspec != null) pubspecFields.addAll(resolvedPubspec);
      if (resolvedDeps != null) pubspecFields["dependencies"] = resolvedDeps;

      if (contents == null) contents = [d.libDir(name, "$name $version")];
      contents = [d.file("pubspec.yaml", yaml(pubspecFields))]
          ..addAll(contents);

      var packages = _packages.putIfAbsent(name, () => []);
      packages.add(new _ServedPackage(pubspecFields, contents));
    }));
  }

  /// Serves the versions of [package] and all its dependencies that are
  /// currently depended on by pub.
  void serveRealPackage(String package) {
    _addPackage(name) {
      if (_packages.containsKey(name)) return;
      _packages[name] = [];

      var root = packagePath(name);
      var pubspec = new Map.from(loadYaml(
          readTextFile(p.join(root, 'pubspec.yaml'))));

      // Remove any SDK constraints since we don't have a valid SDK version
      // while testing.
      pubspec.remove('environment');

      _packages[name].add(new _ServedPackage(pubspec, [
        d.file('pubspec.yaml', yaml(pubspec)),
        new d.DirectoryDescriptor.fromFilesystem('lib', p.join(root, 'lib'))
      ]));

      if (pubspec.containsKey('dependencies')) {
        pubspec['dependencies'].keys.forEach(_addPackage);
      }
    }

    _addPackage(package);
  }

  /// Returns a Future that completes once all the [serve] calls have been fully
  /// processed.
  Future _await() {
    if (_futures.futures.isEmpty) return new Future.value();
    return _futures.future.then((_) {
      _futures = new FutureGroup();
    });
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

  Version get version => new Version.parse(pubspec['version']);

  _ServedPackage(this.pubspec, this.contents);
}
