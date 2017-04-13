// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';

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
  Module.fromJson(List<List<dynamic>> json)
      : id = new ModuleId.fromJson(json[0]),
        assetIds = new Set<AssetId>.from(
            json[1].map((id) => new AssetId.deserialize(id))),
        directDependencies = new Set<AssetId>.from(
            json[2].map((d) => new AssetId.deserialize(d)));

  List<List<dynamic>> toJson() => [
        id.toJson(),
        assetIds.map((id) => id.serialize()).toList(),
        directDependencies.map((d) => d.serialize()).toList(),
      ];
}

/// Serializable identifier of a [Module].
///
/// A [Module] can only be a part of a single package, and must have a unique
/// name within that package.
class ModuleId {
  final String package;
  final String name;

  const ModuleId(this.package, this.name);
  ModuleId.fromJson(List<String> json)
      : package = json[0],
        name = json[1];

  List<String> toJson() => <String>[package, name];

  @override
  String toString() => 'ModuleId: $package|$name';

  @override
  bool operator ==(other) =>
      other is ModuleId && other.package == package && other.name == this.name;

  @override
  int get hashCode => '$package|$name'.hashCode;
}
