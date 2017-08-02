// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import 'summaries.dart';

/// Serializable object that describes a single `module`.
///
/// A `module` is a set of dart [AssetId]s contained in the module and a list of
/// other [AssetId]s which are direct dependencies.
///
/// Note that all [assetIds] must be in the same package, but
/// [directDependencies] may be from any package.
///
/// Use a [ModuleReader#readTransitiveDeps] to get the transitive dependencies
/// of a module.
class Module {
  final ModuleId id;
  final Set<AssetId> assetIds;
  final Set<AssetId> directDependencies;

  Module(this.id, this.assetIds, this.directDependencies);

  /// Creates a [Module] from [json] which should be a [List] that was created
  /// with [toJson].
  ///
  /// It should contain exactly 3 entries, representing the [id], [assetIds],
  /// and [directDependencies] fields in that order.
  Module.fromJson(List<List<dynamic>> json)
      : id = new ModuleId.fromJson(json[0]),
        assetIds = new Set<AssetId>.from(
            json[1].map((id) => new AssetId.deserialize(id))),
        directDependencies = new Set<AssetId>.from(
            json[2].map((d) => new AssetId.deserialize(d)));

  /// Serialize this [Module] to a nested [List] which can be encoded with
  /// `JSON.encode` and then decoded later with `JSON.decode`.
  ///
  /// The resulting [List] will have 3 values, representing the [id],
  /// [assetIds], and [directDependencies] fields in that order.
  List<List<dynamic>> toJson() => [
        id.toJson(),
        assetIds.map((id) => id.serialize()).toList(),
        directDependencies.map((d) => d.serialize()).toList(),
      ];

  String toString() => '''
$id
assetIds: $assetIds
directDependencies: $directDependencies''';
}

/// Serializable identifier of a [Module].
///
/// A [Module] can only be a part of a single package, and must have a unique
/// [name] within that package.
///
/// The [dir] is the top level directory under the package where the module
/// lives (such as `lib`, `web`, `test`, etc).
class ModuleId {
  final String dir;
  final String name;
  final String package;

  AssetId get unlinkedSummaryId =>
      _moduleAssetWithExtension(unlinkedSummaryExtension);

  AssetId get linkedSummaryId =>
      _moduleAssetWithExtension(linkedSummaryExtension);

  AssetId get jsId => _moduleAssetWithExtension('.js');

  AssetId get jsSourceMapId => jsId.addExtension('.map');

  const ModuleId(this.package, this.name, this.dir);

  /// Creates a [ModuleId] from [json] which should be a [List] that was created
  /// with [toJson].
  ///
  /// It should contain exactly 2 entries, representing the [package] and [name]
  /// fields in that order.
  ModuleId.fromJson(List<String> json)
      : package = json[0],
        name = json[1],
        dir = json[2];

  /// Serialize this [ModuleId] to a nested [List] which can be encoded with
  /// `JSON.encode` and then decoded later with `JSON.decode`.
  ///
  /// The resulting [List] will have 3 values, representing the [package],
  /// [name], and [dir] fields in that order.
  List<String> toJson() => <String>[package, name, dir];

  @override
  String toString() => 'ModuleId: $package|$dir/$name';

  @override
  bool operator ==(other) =>
      other is ModuleId &&
      other.package == package &&
      other.name == name &&
      other.dir == dir;

  @override
  int get hashCode => package.hashCode ^ name.hashCode ^ dir.hashCode;

  /// Returns an asset for this module with the given [extension].
  AssetId _moduleAssetWithExtension(String extension) {
    return new AssetId(package, p.join(dir, '$name$extension'));
  }
}
