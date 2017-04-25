// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import 'module.dart';
import 'module_computer.dart';
import 'module_reader.dart';
import 'util.dart';

/// Computes the ideal set of [Module]s for top level directories in a package,
/// and outputs a single `.moduleConfig` file in each one.
class ModuleConfigTransformer extends AggregateTransformer {
  ModuleConfigTransformer();

  @override
  String classifyPrimary(AssetId id) {
    if (p.extension(id.path) != '.dart') return null;
    return topLevelDir(id.path);
  }

  @override
  Future apply(AggregateTransform transform) async {
    var moduleMode =
        transform.key == 'lib' ? ModuleMode.public : ModuleMode.private;
    var allAssets = await transform.primaryInputs.toList();
    var modules = await computeModules(moduleMode, allAssets);
    var encoded = JSON.encode(modules);
    transform.addOutput(new Asset.fromString(
        new AssetId(
            transform.package, p.url.join(transform.key, moduleConfigName)),
        encoded));
  }
}
