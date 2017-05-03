// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

import '../../dart.dart';
import '../../io.dart';

/// Copies the `dart_sdk.js` and `require.js` amd files from the SDK into each
/// entrypoint dir.
class DartDevcResourceTransformer extends AggregateTransformer
    implements DeclaringAggregateTransformer {
  /// Group files by output directory, skipping `lib` and `bin`.
  @override
  String classifyPrimary(AssetId id) {
    if (p.extension(id.path) != '.dart') return null;
    var dir = topLevelDir(id.path);
    if (dir == 'lib' || dir == 'bin') return null;
    return p.url.dirname(id.path);
  }

  @override
  Future apply(AggregateTransform transform) async {
    // If there are no entrypoints then skip this folder.
    var hasEntrypoint = false;
    await for (var asset in transform.primaryInputs) {
      if (isEntrypoint(parseCompilationUnit(await asset.readAsString(),
          parseFunctionBodies: false))) {
        hasEntrypoint = true;
        break;
      }
    }
    if (!hasEntrypoint) return;

    var sdk = cli_util.getSdkDir();

    // Copy the dart_sdk.js file for AMD into the output folder.
    var sdkJsOutputId = new AssetId(
        transform.package, p.url.join(transform.key, 'dart_sdk.js'));
    var sdkAmdJsPath = p.url.join(sdk.path, 'lib/dev_compiler/amd/dart_sdk.js');
    transform
        .addOutput(new Asset.fromFile(sdkJsOutputId, new File(sdkAmdJsPath)));

    // Copy the require.js file for AMD into the output folder.
    var requireJsOutputId =
        new AssetId(transform.package, p.url.join(transform.key, 'require.js'));
    var requireJsPath = p.url.join(sdk.path, 'lib/dev_compiler/amd/require.js');
    transform.addOutput(
        new Asset.fromFile(requireJsOutputId, new File(requireJsPath)));
  }

  @override
  Future declareOutputs(DeclaringAggregateTransform transform) async {
    transform.declareOutput(new AssetId(
        transform.package, p.url.join(transform.key, 'dart_sdk.js')));
    transform.declareOutput(new AssetId(
        transform.package, p.url.join(transform.key, 'require.js')));
  }
}
