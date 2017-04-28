// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import '../../dart.dart';
import '../../io.dart';
import 'module.dart';
import 'module_reader.dart';

class DartDevcBootstrapTransformer extends Transformer {
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
    await _bootstrapEntryPoint(transform.primaryInput.id, transform);
  }
}

/// Bootstraps the js module for the entrypoint dart file [entrypointId] with
/// two additional JS files:
///
/// * A `$entrypointId.js` file which is the main entrypoint for the app. It
///   injects a script tag whose src is `require.js` and whose `data-main`
///   attribute points at a `$entrypointId.bootstrap.js` file.
/// * A `$entrypointId.bootstrap.js` file which invokes the top level `main`
///   function from the entrypoint module, after performing some necessary SDK
///   setup.
Future _bootstrapEntryPoint(AssetId entrypointId, Transform transform) async {
  var moduleReader = new ModuleReader(transform.readInputAsString);
  var module = await moduleReader.moduleFor(entrypointId);

  var appModuleName =
      p.relative(module.id.name, from: p.dirname(entrypointId.path));

  // TODO(jakemac53): Sane module name creation, this only works in the most
  // basic of cases.
  //
  // See https://github.com/dart-lang/sdk/issues/27262 for the root issue which
  // will allow us to not rely on the naming schemes that dartdevc uses
  // internally, but instead specify our own.
  var appModuleScope = p.url
      .split(moduleId.path.substring(0, moduleId.path.indexOf('.dart')))
      .join("__");
  var bootstrapContent = '''
  require(["$appModuleName", "dart_sdk"], function(app, dart_sdk) {
  dart_sdk._isolate_helper.startRootIsolate(() => {}, []);
  app.$appModuleScope.main();
  });
  ''';
  transform.addOutput(new Asset.fromString(bootstrapId, bootstrapContent));

  var bootstrapModuleName = p.withoutExtension(
      p.relative(bootstrapId.path, from: p.dirname(entryPointId.path)));
  var entryPointContent = '''
  var el = document.createElement("script");
  el.defer = true;
  el.async = false;
  el.src = "require.js";
  el.setAttribute("data-main", "$bootstrapModuleName");
  document.head.appendChild(el);
  ''';
  transform.addOutput(new Asset.fromString(entryPointId, entryPointContent));

  // // The AMD bootstrap script, initializes the dart SDK, calls `require` with
  // // the module for  `jsModuleId` and invokes its main.
  // var bootstrapId = dartId.addExtension('.bootstrap.js');
  // // The entry point for the app, injects a deferred script tag whose src is
  // // `require.js`, with the `data-main` attribute set to the `bootstrapId`
  // // module.
  // var entryPointId = dartId.addExtension('.js');
  //
  // // Create the actual bootsrap.
  // _createAmdBootstrap(entryPointId, bootstrapId, jsModuleId, transform);
}
