// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';

import '../../dart.dart';
import '../../io.dart';
import 'dartdevc.dart';
import 'module_reader.dart';

class DartDevcBootstrapTransformer extends Transformer {
  final BarbackMode mode;

  DartDevcBootstrapTransformer(this.mode);

  @override
  bool isPrimary(AssetId id) {
    // Only `.dart` files not under `lib` or `bin` are considered candidates for
    // being dartdevc application entrypoints.
    if (id.extension != '.dart') return false;
    var dir = topLevelDir(id.path);
    return dir != 'lib' && dir != 'bin';
  }

  @override
  Future apply(Transform transform) async {
    var parsed =
        parseCompilationUnit(await transform.primaryInput.readAsString());
    if (!isEntrypoint(parsed)) return;
    var outputs = await bootstrapDartDevcEntrypoint(transform.primaryInput.id,
        mode, new ModuleReader(transform.readInputAsString));
    await Future.wait(outputs.values
        .map((futureAsset) async => transform.addOutput(await futureAsset)));
  }
}
