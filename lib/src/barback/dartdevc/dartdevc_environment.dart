// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

import 'dartdevc.dart';
import 'module_computer.dart';
import 'module_reader.dart';
import 'scratch_space.dart';
import 'summaries.dart';

import '../../dart.dart';
import '../../io.dart';
import '../../package_graph.dart';

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

  DartDevcEnvironment(this._barback, this._mode, this._environmentConstants,
      PackageGraph packageGraph)
      : _assetCache = new _AssetCache(packageGraph) {
    _moduleReader = new ModuleReader(_readModule);
  }

  /// Attempt to get an [Asset] by [id], completes with an
  /// [AssetNotFoundException] if the asset couldn't be built.
  Future<Asset> getAssetById(AssetId id) {
    if (_assetCache[id] == null) {
      _assetCache[id] = _buildAsset(id);
    }
    return _assetCache[id];
  }

  /// Invalidates [package] and all packages that depend on [package].
  void invalidatePackage(String package) {
    _assetCache.invalidatePackage(package);
  }

  /// Handles building all assets that we know how to build.
  ///
  /// Completes with an [AssetNotFoundException] if the asset couldn't be built.
  Future<Asset> _buildAsset(AssetId id) async {
    Asset asset;
    if (id.path.endsWith(unlinkedSummaryExtension)) {
      asset = await _buildUnlinkedSummary(id);
    } else if (id.path.endsWith(linkedSummaryExtension)) {
      asset = await _buildLinkedSummary(id);
    } else if (id.path.endsWith('.bootstrap.js') ||
        id.path.endsWith('.dart.js')) {
      asset = await _buildBootstrapJs(id);
    } else if (id.path.endsWith('require.js') ||
        id.path.endsWith('dart_sdk.js')) {
      asset = await _buildJsResource(id);
    } else if (id.path.endsWith('require.js.map') ||
        id.path.endsWith('dart_sdk.js.map')) {
      throw new AssetNotFoundException(id);
    } else if (id.path.endsWith('.js') || id.path.endsWith('.js.map')) {
      asset = await _buildJsModule(id);
    } else if (id.path.endsWith(moduleConfigName)) {
      asset = await _buildModuleConfig(id);
    }
    if (asset == null) throw new AssetNotFoundException(id);
    return asset;
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

  /// Builds an unlinked analyzer summary asset at [id].
  Future<Asset> _buildUnlinkedSummary(AssetId id) async {
    assert(id.path.endsWith(unlinkedSummaryExtension));
    var module = await _moduleReader.moduleFor(id);
    var scratchSpace = await ScratchSpace.create(module.assetIds, _readAsBytes);
    var assets = createUnlinkedSummaryForModule(module, scratchSpace, print);
    assets.forEach((id, asset) => _assetCache[id] ??= asset);
    Future.wait(assets.values).then((_) => scratchSpace.delete());
    return assets[id];
  }

  /// Builds a linked analyzer summary asset at [id].
  Future<Asset> _buildLinkedSummary(AssetId id) async {
    assert(id.path.endsWith(linkedSummaryExtension));
    var module = await _moduleReader.moduleFor(id);
    var transitiveModuleDeps = await _moduleReader.readTransitiveDeps(module);
    var unlinkedSummaryIds =
        transitiveModuleDeps.map((depId) => depId.unlinkedSummaryId).toSet();
    var allAssetIds = new Set<AssetId>()
      ..addAll(module.assetIds)
      ..addAll(unlinkedSummaryIds);
    var scratchSpace = await ScratchSpace.create(allAssetIds, _readAsBytes);
    var assets = createLinkedSummaryForModule(
        module, unlinkedSummaryIds, scratchSpace, print);
    assets.forEach((id, asset) => _assetCache[id] ??= asset);
    Future.wait(assets.values).then((_) => scratchSpace.delete());
    return assets[id];
  }

  /// Builds `.bootstrap.js` and `.dart.js` files that bootstrap dartdevc apps.
  ///
  /// Both are always built and cached regardless of which is requested since
  /// they will both ultimately be needed.
  Future<Asset> _buildBootstrapJs(AssetId id) async {
    assert(id.path.endsWith('.bootstrap.js') || id.path.endsWith('.dart.js'));
    // Skip entrypoints under lib
    if (topLevelDir(id.path) == 'lib') return null;

    // Remove the `.js` extension.
    var dartId = id.changeExtension('');
    // Conditionally change the `.bootstrap` extension to a `.dart` extension.
    if (dartId.extension == '.bootstrap') dartId.changeExtension('.dart');
    assert(dartId.extension == '.dart');

    var dartAsset = await _barback.getAssetById(dartId);
    var parsed = parseCompilationUnit(await dartAsset.readAsString());
    if (!isEntrypoint(parsed)) return null;
    var assets = bootstrapDartDevcEntrypoint(dartId, _mode, _moduleReader);
    assets.forEach((id, asset) => _assetCache[id] ??= asset);
    return assets[id];
  }

  /// Builds the js module at [id] using dartdevc.
  Future<Asset> _buildJsModule(AssetId id) async {
    assert(id.extension == '.js');
    var module = await _moduleReader.moduleFor(id);
    var transitiveModuleDeps = await _moduleReader.readTransitiveDeps(module);
    var linkedSummaryIds =
        transitiveModuleDeps.map((depId) => depId.linkedSummaryId).toSet();
    var allAssetIds = new Set<AssetId>()
      ..addAll(module.assetIds)
      ..addAll(linkedSummaryIds);
    var scratchSpace = await ScratchSpace.create(allAssetIds, _readAsBytes);
    var assets = createDartdevcModule(module, scratchSpace, linkedSummaryIds,
        _environmentConstants, _mode, print);
    assets.forEach((id, asset) => _assetCache[id] ??= asset);
    Future.wait(assets.values).then((_) => scratchSpace.delete());
    return assets[id];
  }

  /// Builds the `dart_sdk.js` or `require.js` assets by copying them from the
  /// sdk.
  Future<Asset> _buildJsResource(AssetId id) async {
    var sdk = cli_util.getSdkDir();

    switch (p.url.basename(id.path)) {
      case 'dart_sdk.js':
        var sdkAmdJsPath =
            p.url.join(sdk.path, 'lib/dev_compiler/amd/dart_sdk.js');
        return new Asset.fromFile(id, new File(sdkAmdJsPath));
      case 'require.js':
        var requireJsPath =
            p.url.join(sdk.path, 'lib/dev_compiler/amd/require.js');
        return new Asset.fromFile(id, new File(requireJsPath));
      default:
        return null;
    }
  }

  /// Helper to read a module config file, used by [_moduleReader].
  ///
  /// Skips barback and reads directly from [this] since we create all these
  /// files.
  Future<String> _readModule(AssetId moduleConfigId) async {
    var asset = await getAssetById(moduleConfigId);
    return asset.readAsString();
  }

  /// Reads [id] as a stream of bytese.
  ///
  /// All `.dart` files are read from [_barback], and all other files are read
  /// from [this].
  Stream<List<int>> _readAsBytes(AssetId id) {
    var controller = new StreamController<List<int>>();
    () async {
      var asset = id.extension == '.dart'
          ? await _barback.getAssetById(id)
          : await getAssetById(id);
      await controller.addStream(asset.read());
      controller.close();
    }();
    return controller.stream;
  }
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
