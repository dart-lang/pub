// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:barback/barback.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:package_resolver/package_resolver.dart';
import 'package:pub_semver/pub_semver.dart';

import '../compiler.dart';
import '../io.dart';
import '../package.dart';
import '../package_graph.dart';
import '../preprocess.dart';
import '../sdk.dart' as sdk;

/// The path to the lib directory of the compiler_unsupported package used by
/// pub.
///
/// This is used to make sure dart2js is running against its own version of its
/// internal libraries when running from the pub repo. It's `null` if we're
/// running from the Dart repo or from the built SDK.
final Future<String> _compilerUnsupportedLib = (() async {
  if (runningFromSdk) return null;
  if (runningFromDartRepo) return null;

  return p
      .fromUri(await PackageResolver.current.urlFor('compiler_unsupported'));
})();

final _zlib = new ZLibCodec();

/// An implementation of barback's [PackageProvider] interface so that barback
/// can find assets within pub packages.
class PubPackageProvider implements StaticPackageProvider {
  final PackageGraph _graph;
  final List<String> staticPackages;

  Iterable<String> get packages =>
      _graph.packages.keys.toSet().difference(staticPackages.toSet());

  PubPackageProvider(PackageGraph graph, Compiler compiler)
      : _graph = graph,
        staticPackages = [r"$pub", r"$sdk"]..addAll(graph.packages.keys
            .where((p) => graph.isPackageStatic(p, compiler)));

  Future<Asset> getAsset(AssetId id) async {
    // "$pub" is a psuedo-package that allows pub's transformer-loading
    // infrastructure to share code with pub proper.
    if (id.package == r'$pub') {
      var components = p.url.split(id.path);
      assert(components.isNotEmpty);
      assert(components.first == 'lib');
      components[0] = 'dart';
      var file = assetPath(p.joinAll(components));
      _assertExists(file, id);

      // Barback may not be in the package graph if there are no user-defined
      // transformers being used at all. The "$pub" sources are still provided,
      // but will never be loaded.
      if (!_graph.packages.containsKey("barback")) {
        return new Asset.fromPath(id, file);
      }

      var versions = mapMap/*<String, Package, String, Version>*/(
          _graph.packages,
          value: (_, package) => package.version);
      var contents = readTextFile(file);
      contents = preprocess(contents, versions, p.toUri(file));
      return new Asset.fromString(id, contents);
    }

    // "$sdk" is a pseudo-package that provides access to the Dart library
    // sources in the SDK. The dart2js transformer uses this to locate the Dart
    // sources for "dart:" libraries.
    if (id.package == r'$sdk') {
      // The asset path contains two "lib" entries. The first represents pub's
      // concept that all public assets are in "lib". The second comes from the
      // organization of the SDK itself. Strip off the first. Leave the second
      // since dart2js adds it and expects it to be there.
      var parts = p.split(p.fromUri(id.path));
      assert(parts.isNotEmpty && parts[0] == 'lib');
      parts = parts.skip(1).toList();

      var compilerUnsupportedLib = await _compilerUnsupportedLib;
      if (compilerUnsupportedLib == null) {
        var file = p.join(sdk.rootDirectory, p.joinAll(parts));
        _assertExists(file, id);
        return new Asset.fromPath(id, file);
      }

      // If we're running from pub's repo, our version of dart2js comes from
      // compiler_unsupported and may expect different SDK sources than the
      // actual SDK we're using. Handily, compiler_unsupported contains a full
      // (ZLib-encoded) copy of the SDK, so we load sources from that instead.
      var file =
          p.join(compilerUnsupportedLib, 'sdk', p.joinAll(parts.skip(1))) + "_";
      _assertExists(file, id);
      return new Asset.fromStream(id,
          new LazyStream(() => _zlib.decoder.bind(new File(file).openRead())));
    }

    var nativePath = p.fromUri(id.path);
    var file = _graph.packages[id.package].path(nativePath);
    _assertExists(file, id);
    return new Asset.fromPath(id, file);
  }

  /// Throw an [AssetNotFoundException] for [id] if [path] doesn't exist.
  void _assertExists(String path, AssetId id) {
    if (!fileExists(path)) throw new AssetNotFoundException(id);
  }

  Stream<AssetId> getAllAssetIds(String packageName) {
    if (packageName == r'$pub') {
      // "$pub" is a pseudo-package that allows pub's transformer-loading
      // infrastructure to share code with pub proper. We provide it only during
      // the initial transformer loading process.
      var dartPath = assetPath('dart');
      return new Stream.fromIterable(listDir(dartPath, recursive: true)
          // Don't include directories.
          .where((file) => p.extension(file) == ".dart")
          .map((library) {
        var idPath = p.join('lib', p.relative(library, from: dartPath));
        return new AssetId('\$pub', p.toUri(idPath).toString());
      }));
    } else if (packageName == r'$sdk') {
      return StreamCompleter.fromFuture(() async {
        var compilerUnsupportedLib = await _compilerUnsupportedLib;
        // "$sdk" is a pseudo-package that allows the dart2js transformer to
        // find the Dart core libraries without hitting the file system
        // directly. This ensures they work with source maps.
        var libPath = compilerUnsupportedLib == null
            ? p.join(sdk.rootDirectory, "lib")
            : p.join(compilerUnsupportedLib, "sdk");
        var files = listDir(libPath, recursive: true);

        if (compilerUnsupportedLib != null) {
          // compiler_unsupported's SDK sources are ZLib-encoded; to indicate
          // this, they end in "_". We serve them decoded, though, so we strip
          // the underscore to get the asset paths.
          var trailingUnderscore = new RegExp(r"_$");
          files = files.map((file) => file.replaceAll(trailingUnderscore, ""));
        }

        return new Stream.fromIterable(
            files.where((file) => p.extension(file) == ".dart").map((file) {
          var idPath = p.join("lib", "lib", p.relative(file, from: libPath));
          return new AssetId('\$sdk', p.toUri(idPath).toString());
        }));
      }());
    } else {
      var package = _graph.packages[packageName];
      return new Stream.fromIterable(
          package.listFiles(beneath: 'lib').map((file) {
        return new AssetId(
            packageName, p.toUri(package.relative(file)).toString());
      }));
    }
  }
}
