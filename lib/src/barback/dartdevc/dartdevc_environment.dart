// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:barback/barback.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

import '../../io.dart';
import '../../log.dart' as log;
import '../../package_graph.dart';
import 'dartdevc.dart';
import 'module.dart';
import 'module_computer.dart';
import 'module_reader.dart';
import 'scratch_space.dart';
import 'summaries.dart';
import 'workers.dart';

/// Handles running dartdevc on top of a [Barback] instance.
///
/// You must call [invalidatePackage] any time a package is updated, since
/// barback doesn't provide a mechanism to tell you which files have changed.
class DartDevcEnvironment {
  final _AssetCache _assetCache;
  final Barback _barback;
  final Map<String, String> _environmentConstants;
  final BarbackMode _mode;
  ModuleReader _moduleReader;
  final PackageGraph _packageGraph;
  ScratchSpace _scratchSpace;

  DartDevcEnvironment(
      this._barback, this._mode, this._environmentConstants, this._packageGraph)
      : _assetCache = new _AssetCache(_packageGraph) {
    _moduleReader = new ModuleReader(_readModule);
    _scratchSpace = new ScratchSpace(_getAsset);
  }

  /// Deletes the [_scratchSpace] and shuts down the workers.
  Future cleanUp() {
    return Future.wait([
      _scratchSpace.delete(),
      // These should get terminated automatically when this process exits, but
      // we end them explicitly just to be safe.
      analyzerDriver.terminateWorkers(),
      dartdevcDriver.terminateWorkers()
    ]);
  }

  /// Builds all dartdevc files required for all app entrypoints in
  /// [inputAssets].
  ///
  /// Returns only the `.js` files which are required to load the apps.
  Future<AssetSet> doFullBuild(AssetSet inputAssets, logError(error)) {
    var completer = new Completer<AssetSet>();
    var jsAssets = new AssetSet();
    runZoned(() async {
      try {
        var modulesToBuild = new Set<ModuleId>();
        for (var asset in inputAssets) {
          try {
            if (asset.id.package != _packageGraph.entrypoint.root.name) {
              continue;
            }
            if (asset.id.extension != '.dart') continue;
            // We only care about real entrypoint modules, we collect those and all
            // their transitive deps.
            if (!await isAppEntryPoint(asset.id, _barback.getAssetById)) {
              continue;
            }

            // Build the entrypoint js files, and collect the set of transitive
            // modules that are required (will be built later).
            var futureAssets = _buildAsset(asset.id.addExtension('.js'));
            jsAssets.addAll(await Future.wait(futureAssets.values));
            var module = await _moduleReader.moduleFor(asset.id);
            modulesToBuild.add(module.id);
            modulesToBuild
                .addAll(await _moduleReader.readTransitiveDeps(module));
          } catch (e) {
            logError(e);
          }
        }

        // Build all required modules for the apps that were discovered.
        var allFutureAssets = <Future<Asset>>[];
        for (var module in modulesToBuild) {
          var futureAssets = _buildAsset(module.jsId).values;
          allFutureAssets.addAll(futureAssets);
          // Add explicit listeners on all `Future`s to make sure we log all
          // errors. The `Future.wait` below only captures the first error.
          for (var futureAsset in futureAssets) {
            futureAsset.catchError(logError);
          }
        }
        jsAssets.addAll(await Future.wait(allFutureAssets));
      } finally {
        // Wait to complete until the last moment possible so that we log all
        // errors that are encountered.
        completer.complete(jsAssets);
      }
    }, onError: (e) {
      logError(e);
    });

    return completer.future;
  }

  /// Attempt to get an [Asset] by [id], completes with an
  /// [AssetNotFoundException] if the asset couldn't be built.
  Future<Asset> getAssetById(AssetId id) {
    var completer = new Completer<Asset>();
    var loggedErrors = new Set<dynamic>();

    // Handles errors in a uniform way:
    //   * logs all errors that aren't `AssetNotFoundException`s.
    //   * makes sure to only log an error once.
    //   * converts all errors to `AssetNotFoundException`s if they weren't
    //     already.
    handleError(e, s) {
      if (e is! AssetNotFoundException) {
        if (!loggedErrors.contains(e)) {
          loggedErrors.add(e);
          log.error(log.red('Error creating $id'), e, s);
        }
        e = new AssetNotFoundException(id);
      }
      return e;
    }

    runZoned(() async {
      if (_assetCache[id] == null) {
        if (_isEntrypointId(id)) {
          var dartId = _entrypointDartId(id);
          if (dartId != null &&
              await isAppEntryPoint(dartId, _barback.getAssetById)) {
            _buildAsset(id);
          }
        } else {
          _buildAsset(id);
        }
      }
      _assetCache[id].then((asset) {
        if (completer.isCompleted) return;
        if (asset == null) throw new AssetNotFoundException(id);
        completer.complete(asset);
      }).catchError((e, s) {
        e = handleError(e, s);
        if (completer.isCompleted) return;
        completer.completeError(e);
      });
    }, onError: (e, s) {
      e = handleError(e, s);
      if (completer.isCompleted) return;
      // In the general case we want to just return the value from the cache
      // which will complete with an error (possibly this one).
      //
      // However, if we failed to insert an item in the cache for `id` then we
      // will likely never complete properly, so we complete with this error.
      if (_assetCache[id] == null) {
        completer.completeError(e);
      }
    });

    return completer.future;
  }

  /// Invalidates [package] and all packages that depend on [package].
  void invalidatePackage(String package) {
    _assetCache.invalidatePackage(package);
    _scratchSpace.deletePackageFiles(package,
        isRootPackage: package == _packageGraph.entrypoint.root.name);
  }

  /// Handles building all assets that we know how to build.
  ///
  /// Completes with an [AssetNotFoundException] if the asset couldn't be built.
  Map<AssetId, Future<Asset>> _buildAsset(AssetId id) {
    if (_assetCache[id] != null) return {id: _assetCache[id]};
    Map<AssetId, Future<Asset>> assets;
    if (id.path.endsWith(unlinkedSummaryExtension)) {
      assets = {id: createUnlinkedSummary(id, _moduleReader, _scratchSpace)};
    } else if (id.path.endsWith(linkedSummaryExtension)) {
      assets = {id: createLinkedSummary(id, _moduleReader, _scratchSpace)};
    } else if (_isEntrypointId(id)) {
      var dartId = _entrypointDartId(id);
      if (dartId != null) {
        assets = bootstrapDartDevcEntrypoint(
            dartId, _mode, _moduleReader, _barback.getAssetById);
      }
    } else if (id.path.endsWith('require.js') ||
        id.path.endsWith('dart_sdk.js')) {
      assets = {id: _buildJsResource(id)};
    } else if (id.path.endsWith('require.js.map') ||
        id.path.endsWith('dart_sdk.js.map')) {
      assets = {id: new Future.error(new AssetNotFoundException(id))};
    } else if (id.path.endsWith('.js') || id.path.endsWith('.js.map')) {
      var jsId = id.extension == '.map' ? id.changeExtension('') : id;
      assets = createDartdevcModule(
          jsId, _moduleReader, _scratchSpace, _environmentConstants, _mode);
      // Pre-emptively start building all transitive js deps under the
      // assumption they will be needed in the near future.
      () async {
        var module = await _moduleReader.moduleFor(jsId);
        var deps = await _moduleReader.readTransitiveDeps(module);
        deps.forEach((moduleId) => getAssetById(moduleId.jsId));
      }();
    } else if (id.path.endsWith(moduleConfigName)) {
      assets = {id: _buildModuleConfig(id)};
    }
    assets ??= <AssetId, Future<Asset>>{};

    for (var id in assets.keys) {
      _assetCache[id] = assets[id];
    }
    return assets;
  }

  /// Builds a module config asset at [id].
  Future<Asset> _buildModuleConfig(AssetId id) async {
    assert(id.path.endsWith(moduleConfigName));
    var moduleDir = topLevelDir(id.path);
    var allAssets = await _barback.getAllAssets();
    var moduleAssets = allAssets.where((asset) =>
        asset.id.package == id.package &&
        asset.id.extension == '.dart' &&
        topLevelDir(asset.id.path) == moduleDir);
    var moduleMode =
        moduleDir == 'lib' ? ModuleMode.public : ModuleMode.private;
    var modules = await computeModules(moduleMode, moduleAssets);
    var encoded = JSON.encode(modules);
    return new Asset.fromString(id, encoded);
  }

  /// Builds the `dart_sdk.js` or `require.js` assets by copying them from the
  /// SDK.
  Future<Asset> _buildJsResource(AssetId id) async {
    var sdk = cli_util.getSdkDir();

    switch (p.url.basename(id.path)) {
      case 'dart_sdk.js':
        var sdkAmdJsPath =
            p.url.join(sdk.path, 'lib/dev_compiler/amd/dart_sdk.js');
        return new Asset.fromPath(id, sdkAmdJsPath);
      case 'require.js':
        var requireJsPath =
            p.url.join(sdk.path, 'lib/dev_compiler/amd/require.js');
        return new Asset.fromFile(id, new File(requireJsPath));
      default:
        return null;
    }
  }

  /// Whether or not this looks like a request for an entrypoint or bootstrap
  /// file.
  bool _isEntrypointId(AssetId id) =>
      id.path.endsWith('.bootstrap.js') ||
      id.path.endsWith('.bootstrap.js.map') ||
      id.path.endsWith('.dart.js') ||
      id.path.endsWith('.dart.js.map');

  /// Helper to read a module config file, used by [_moduleReader].
  ///
  /// Skips barback and reads directly from [this] since we create all these
  /// files.
  Future<String> _readModule(AssetId moduleConfigId) async {
    var asset = await getAssetById(moduleConfigId);
    return asset.readAsString();
  }

  /// Gets an [Asset] by [id] asynchronously.
  ///
  /// All `.dart` files are read from [_barback], and all other files are read
  /// from [this]. This is because the only files we care about from barback are
  /// `.dart` files.
  Future<Asset> _getAsset(AssetId id) async {
    var asset = id.extension == '.dart'
        ? await _barback.getAssetById(id)
        : await getAssetById(id);
    if (asset == null) throw new AssetNotFoundException(id);
    return asset;
  }
}

/// Gives the dart entrypoint [AssetId] for a bootstrap js [id].
AssetId _entrypointDartId(AssetId id) {
  if (id.extension == '.map') id = id.changeExtension('');
  assert(id.path.endsWith('.bootstrap.js') || id.path.endsWith('.dart.js'));
  // Skip entrypoints under lib.
  if (topLevelDir(id.path) == 'lib') return null;

  // Remove the `.js` extension.
  var dartId = id.changeExtension('');
  // Conditionally change the `.bootstrap` extension to a `.dart` extension.
  if (dartId.extension == '.bootstrap') dartId.changeExtension('.dart');
  assert(dartId.extension == '.dart');
  return dartId;
}

/// Manages a set of cached future [Asset]s.
class _AssetCache {
  /// [Asset]s are indexed first by package and then path, this allows us to
  /// invalidate whole packages efficiently.
  final _assets = <String, Map<String, Future<Asset>>>{};

  final PackageGraph _packageGraph;

  _AssetCache(this._packageGraph);

  Future<Asset> operator [](AssetId id) {
    var packageCache = _assets[id.package];
    if (packageCache == null) return null;
    return packageCache[id.path];
  }

  void operator []=(AssetId id, Future<Asset> asset) {
    var packageCache =
        _assets.putIfAbsent(id.package, () => <String, Future<Asset>>{});
    packageCache[id.path] = asset;
  }

  /// Invalidates [package] and all packages that depend on [package].
  void invalidatePackage(String packageNameToInvalidate) {
    _assets.remove(packageNameToInvalidate);
    // Also invalidate any package with a transitive dep on the invalidated
    // package.
    var packageToInvalidate = _packageGraph.packages[packageNameToInvalidate];
    for (var packageName in _packageGraph.packages.keys) {
      if (_packageGraph
          .transitiveDependencies(packageName)
          .contains(packageToInvalidate)) {
        _assets.remove(packageName);
      }
    }
  }
}
