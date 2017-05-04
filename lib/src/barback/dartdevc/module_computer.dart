// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import 'module.dart';
import '../../barback.dart';
import '../../io.dart';
import '../../dart.dart' show isEntrypoint, isPart;

/// There are two "types" of modules, `public` and `private`.
///
/// The `public` mode requires that all files are under `lib`.
///
/// The `private` mode requires that no files are under `lib`. All files must
/// still live under some shared top level directory.
enum ModuleMode {
  public,
  private,
}

/// Computes the [Module]s for [srcAssets], or throws an [ArgumentError] if the
/// configuration is invalid.
///
/// All entrypoints are guaranteed their own [Module], unless they are in a
/// strongly connected component with another entrypoint in which case a
/// single [Module] is created for the strongly connected component.
///
/// Note that only entrypoints are guaranteed to exist in any [Module], if
/// an asset exists in [assetIds] but is not reachable from any entrypoint
/// then it will not be contained in any [Module].
///
/// An entrypoint is defined as follows:
///
///   * In [ModuleMode.public], any asset under "lib" but not "lib/src".
///
///   * In [ModuleMode.private], any asset for which [isEntrypoint] returns
///     `true` (for the parsed ast).
///
/// It is guaranteed that no asset will be added to more than one [Module].
Future<List<Module>> computeModules(
    ModuleMode mode, Iterable<Asset> srcAssets) async {
  var dir = topLevelDir(srcAssets.first.id.path);

  // Validate `srcAssets`, must be non-empty and all under the same dir.
  if (srcAssets.isEmpty)
    throw new ArgumentError('Got unexpected empty `srcs`.');
  if (!srcAssets.every((src) => topLevelDir(src.id.path) == dir)) {
    throw new ArgumentError(
        'All srcs must live in the same top level directory.');
  }

  // Validate that the `mode` and `srcAssets` agree.
  switch (mode) {
    case ModuleMode.public:
      if (dir != 'lib') {
        throw new ArgumentError(
            'In `ModuleMode.public` all sources must be under `lib`, but the '
            'given `srcs` are under `$dir`.');
      }
      break;
    case ModuleMode.private:
      if (dir == 'lib') {
        throw new ArgumentError(
            'In `ModuleMode.private` no sources may be under `lib`, but the '
            'given `srcs` are.');
      }
      break;
  }

  // The set of entry points from `srcAssets` based on `mode`.
  var entryIds = new Set<AssetId>();
  // All the `srcAssets` that are part files.
  var partIds = new Set<AssetId>();
  // Invalid assets that should be removed from `srcAssets` after this loop.
  var idsToRemove = <AssetId>[];
  var parsedAssetsById = <AssetId, CompilationUnit>{};
  for (var asset in srcAssets) {
    var id = asset.id;
    var content = await asset.readAsString();
    // Skip errors here, dartdevc gives nicer messages.
    var parsed = parseCompilationUnit(content,
        name: id.path, parseFunctionBodies: false, suppressErrors: true);
    parsedAssetsById[id] = parsed;

    // Skip any files which contain a `dart:_` import.
    if (parsed.directives.any((d) =>
        d is UriBasedDirective && d.uri.stringValue.startsWith('dart:_'))) {
      idsToRemove.add(asset.id);
      continue;
    }

    // Short-circuit for part files.
    if (isPart(parsed)) {
      partIds.add(asset.id);
      continue;
    }

    switch (mode) {
      case ModuleMode.public:
        if (!id.path.startsWith('lib/src/')) entryIds.add(id);
        break;
      case ModuleMode.private:
        if (isEntrypoint(parsed)) entryIds.add(id);
        break;
    }
  }

  srcAssets = srcAssets.where((asset) => !idsToRemove.contains(asset.id));

  // Build the `_AssetNode`s for each asset, skipping part files.
  var nodesById = <AssetId, _AssetNode>{};
  var srcAssetIds = srcAssets.map((asset) => asset.id).toSet();
  var nonPartAssets = srcAssets.where((asset) => !partIds.contains(asset.id));
  for (var asset in nonPartAssets) {
    var node = new _AssetNode.forParsedUnit(
        asset.id, parsedAssetsById[asset.id], srcAssetIds);
    nodesById[asset.id] = node;
  }

  return new _ModuleComputer(entryIds, mode, nodesById)._computeModules();
}

/// An [AssetId] and all of its internal/external deps based on it's
/// [Directive]s.
///
/// Used to compute strongly connected components in the import graph for all
/// "internal" deps. Any "external" deps are ignored during that computation
/// since they are not allowed to be in a strongly connected component with
/// internal deps.
///
/// External deps are used to compute the dependent modules of each module once
/// the modules are decided.
///
/// Part files are also tracked here but ignored during computation of strongly
/// connected components, as they must always be a part of this assets module.
class _AssetNode {
  final AssetId id;

  /// The other internal sources that this file import or exports.
  ///
  /// These may be merged into the same [Module] as this node, and are used when
  /// computing strongly connected components.
  final Set<AssetId> internalDeps;

  /// Part files included by this asset.
  ///
  /// These should always be a part of the same connected component.
  final Set<AssetId> parts;

  /// The deps of this source that are from an external package.
  ///
  /// These are not used in computing strongly connected components (they are
  /// not allowed to be in a strongly connected component with any of our
  /// internal srcs).
  final Set<AssetId> externalDeps;

  /// Order in which this node was discovered.
  int discoveryIndex;

  /// Lowest discoveryIndex for any node this is connected to.
  int lowestLinkedDiscoveryIndex;

  _AssetNode(this.id, this.internalDeps, this.parts, this.externalDeps);

  /// Creates an [_AssetNode] for [id] given a parsed [CompilationUnit] and some
  /// [internalSrcs] which represent other assets that may become part of the
  /// same module.
  factory _AssetNode.forParsedUnit(
      AssetId id, CompilationUnit parsed, Set<AssetId> internalSrcs) {
    var externalDeps = new Set<AssetId>();
    var internalDeps = new Set<AssetId>();
    var parts = new Set<AssetId>();
    for (var directive in parsed.directives) {
      if (directive is! UriBasedDirective) continue;
      var linkedId = importUriToAssetId(
          id, (directive as UriBasedDirective).uri.stringValue);
      if (linkedId == null) continue;
      if (directive is PartDirective) {
        if (!internalSrcs.contains(linkedId)) {
          throw new StateError(
              'Referenced part file $linkedId from $id which is not in the '
              'same package');
        }
        parts.add(linkedId);
      } else if (internalSrcs.contains(linkedId)) {
        internalDeps.add(linkedId);
      } else {
        externalDeps.add(linkedId);
      }
    }
    return new _AssetNode(id, internalDeps, parts, externalDeps);
  }
}

/// Computes the ideal set of [Module]s for a group of [_AssetNode]s.
class _ModuleComputer {
  final Set<AssetId> entrypoints;
  final ModuleMode mode;
  final Map<AssetId, _AssetNode> nodesById;

  _ModuleComputer(this.entrypoints, this.mode, this.nodesById);

  /// Does the actual computation of [Module]s.
  ///
  /// See [computeModules] top level function for more information.
  List<Module> _computeModules() {
    var connectedComponents = _stronglyConnectedComponents();
    var modulesById = _createModulesFromComponents(connectedComponents);
    var modules = _mergeModules(modulesById);
    return _renameSharedModules(modules);
  }

  /// Creates simple modules based strictly off of [connectedComponents].
  ///
  /// This creates more modules than we want, but we collapse them later on.
  Map<ModuleId, Module> _createModulesFromComponents(
      Iterable<Set<_AssetNode>> connectedComponents) {
    var modules = <ModuleId, Module>{};
    for (var componentNodes in connectedComponents) {
      // Name components based on first alphabetically sorted node, preferring
      // public srcs (not under lib/src).
      var sortedNodes = componentNodes.toList()
        ..sort((a, b) => a.id.path.compareTo(b.id.path));
      var primaryNode = sortedNodes.firstWhere(
          (node) => !node.id.path.startsWith('lib/src/'),
          orElse: () => sortedNodes.first);
      var moduleName =
          p.url.split(p.withoutExtension(primaryNode.id.path)).join('__');
      var id = new ModuleId(
          primaryNode.id.package, moduleName, topLevelDir(primaryNode.id.path));
      // Expand to include all the part files of each node, these aren't
      // included as individual `_AssetNodes`s in `connectedComponents`.
      var allAssetIds = componentNodes
          .expand((node) => [node.id]..addAll(node.parts))
          .toSet();
      var allDepIds = new Set<AssetId>();
      for (var node in componentNodes) {
        allDepIds.addAll(node.externalDeps);
        for (var id in node.internalDeps) {
          if (allAssetIds.contains(id)) continue;
          allDepIds.add(id);
        }
      }
      var module = new Module(id, allAssetIds, allDepIds);
      modules[module.id] = module;
    }
    return modules;
  }

  /// Filters [modules] to just those that contain entrypoint assets.
  Set<ModuleId> _entryPointModules(Iterable<Module> modules) {
    var entrypointModules = new Set<ModuleId>();
    for (var module in modules) {
      if (module.assetIds.intersection(entrypoints).isNotEmpty) {
        entrypointModules.add(module.id);
      }
    }
    return entrypointModules;
  }

  /// Creates a map of modules to the entrypoint modules that transitively
  /// depend on those modules.
  Map<ModuleId, Set<ModuleId>> _findReverseEntrypointDeps(
      Set<ModuleId> entrypointModules, Map<ModuleId, Module> modulesById) {
    var reverseDeps = <ModuleId, Set<ModuleId>>{};
    var assetsToModules = <AssetId, Module>{};
    for (var module in modulesById.values) {
      for (var assetId in module.assetIds) {
        assetsToModules[assetId] = module;
      }
    }
    for (var id in entrypointModules) {
      for (var moduleDep
          in _localTransitiveDeps(modulesById[id], assetsToModules)) {
        reverseDeps.putIfAbsent(moduleDep, () => new Set<ModuleId>()).add(id);
      }
    }
    return reverseDeps;
  }

  /// Gets the local (same top level dir of the same package) transitive deps of
  /// [module] using [assetsToModules].
  Set<ModuleId> _localTransitiveDeps(
      Module module, Map<AssetId, Module> assetsToModules) {
    var localTransitiveDeps = new Set<ModuleId>();
    var nextIds = module.directDependencies;
    var seenIds = new Set<AssetId>();
    while (nextIds.isNotEmpty) {
      var ids = nextIds;
      seenIds.addAll(ids);
      nextIds = new Set<AssetId>();
      for (var id in ids) {
        var module = assetsToModules[id];
        if (module == null) continue; // Skip non-local modules
        if (localTransitiveDeps.add(module.id)) {
          nextIds.addAll(module.directDependencies.difference(seenIds));
        }
      }
    }
    return localTransitiveDeps;
  }

  /// Merges [originalModulesById] into a minimum set of [Module]s using the
  /// following rules:
  ///
  ///   * If it is an entrypoint module, skip it.
  ///   * Else merge it into a module whose name is a combination of all the
  ///     entrypoints that import it (create that module if it doesn't exist).
  List<Module> _mergeModules(Map<ModuleId, Module> originalModulesById) {
    var modulesById = new Map<ModuleId, Module>.from(originalModulesById);

    // Maps modules to entrypoint modules that transitively depend on them.
    var entrypointModuleIds = _entryPointModules(modulesById.values);
    var modulesToEntryPoints =
        _findReverseEntrypointDeps(entrypointModuleIds, modulesById);

    for (var moduleId in modulesById.keys.toList()) {
      // Skip entrypoint modules.
      if (entrypointModuleIds.any((id) => id == moduleId)) continue;

      // The entry points that transitively import this module.
      var entrypointIds = modulesToEntryPoints[moduleId];
      if (entrypointIds == null || entrypointIds.isEmpty) {
        throw new StateError(
            'Internal error, found a module that is not depended on by any '
            'entrypoints. Please file an issue at '
            'https://github.com/dart-lang/pub/issues/new');
      }

      // Create a new module based off the name of all entrypoints or merge into
      // an existing one by that name.
      var moduleNames = entrypointIds.map((id) => id.name).toList()..sort();
      var newModuleId = new ModuleId(entrypointIds.first.package,
          moduleNames.join('\$'), entrypointIds.first.dir);
      var newModule = modulesById.putIfAbsent(
          newModuleId,
          () =>
              new Module(newModuleId, new Set<AssetId>(), new Set<AssetId>()));

      var oldModule = modulesById.remove(moduleId);
      // Add all the original assets and deps to the new module.
      newModule.assetIds.addAll(oldModule.assetIds);
      newModule.directDependencies.addAll(oldModule.directDependencies);
      // Clean up deps to remove assetIds, they may have been merged in.
      newModule.directDependencies.removeAll(newModule.assetIds);
    }

    return modulesById.values.toList();
  }

  /// Renames shared [Module]s to something unique and short to avoid issues
  /// with file names that are too long.
  List<Module> _renameSharedModules(List<Module> modules) {
    if (modules.isEmpty) return modules;
    var next = 0;
    return modules.map((module) {
      if (module.id.name.contains('\$')) {
        return new Module(
            new ModuleId(module.id.package,
                '${module.id.dir}__shared_${next++}', module.id.dir),
            module.assetIds,
            module.directDependencies);
      } else {
        return module;
      }
    }).toList();
  }

  /// Computes the strongly connected components reachable from [entrypoints].
  List<Set<_AssetNode>> _stronglyConnectedComponents() {
    var currentDiscoveryIndex = 0;
    // [LinkedHashSet] maintains insertion order which is important!
    var nodeStack = new LinkedHashSet<_AssetNode>();
    var connectedComponents = <Set<_AssetNode>>[];

    void stronglyConnect(_AssetNode node) {
      node.discoveryIndex = currentDiscoveryIndex;
      node.lowestLinkedDiscoveryIndex = currentDiscoveryIndex;
      currentDiscoveryIndex++;
      nodeStack.add(node);

      for (var dep in node.internalDeps) {
        var depNode = nodesById[dep];
        if (depNode.discoveryIndex == null) {
          stronglyConnect(depNode);
          node.lowestLinkedDiscoveryIndex = min(node.lowestLinkedDiscoveryIndex,
              depNode.lowestLinkedDiscoveryIndex);
        } else if (nodeStack.contains(depNode)) {
          node.lowestLinkedDiscoveryIndex = min(node.lowestLinkedDiscoveryIndex,
              depNode.lowestLinkedDiscoveryIndex);
        }
      }

      if (node.discoveryIndex == node.lowestLinkedDiscoveryIndex) {
        var component = new Set<_AssetNode>();

        // Pops the last node off of `nodeStack`, adds it to `component`, and
        // returns it.
        _AssetNode _popAndAddNode() {
          var last = nodeStack.last;
          nodeStack.remove(last);
          component.add(last);
          return last;
        }

        while (_popAndAddNode() != node) {}

        connectedComponents.add(component);
      }
    }

    for (var node in entrypoints.map((e) => nodesById[e])) {
      if (node.discoveryIndex != null) continue;
      stronglyConnect(node);
    }

    return connectedComponents;
  }
}
