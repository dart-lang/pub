// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import '../../dart.dart';
import '../../io.dart';
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
    await _bootstrapEntrypoint(transform.primaryInput.id, transform);
  }
}

/// Bootstraps the js module for the entrypoint dart file [dartEntrypointId]
/// with two additional JS files:
///
/// * A `$dartEntrypointId.js` file which is the main entrypoint for the app. It
///   injects a script tag whose src is `require.js` and whose `data-main`
///   attribute points at a `$dartEntrypointId.bootstrap.js` file.
/// * A `$dartEntrypointId.bootstrap.js` file which invokes the top level `main`
///   function from the entrypoint module, after performing some necessary SDK
///   setup.
Future _bootstrapEntrypoint(
    AssetId dartEntrypointId, Transform transform) async {
  var moduleReader = new ModuleReader(transform.readInputAsString);
  var module = await moduleReader.moduleFor(dartEntrypointId);

  // The path to the entrypoint js module as it should appear in the call to
  // `require` in the bootstrap file.
  var moduleDir = topLevelDir(dartEntrypointId.path);
  var appModulePath = p.relative(p.join(moduleDir, module.id.name),
      from: p.dirname(dartEntrypointId.path));

  // The name of the entrypoint dart library within the entrypoint js module.
  //
  // This is used to invoke `main()` from within the bootstrap script.
  //
  // TODO(jakemac53): Sane module name creation, this only works in the most
  // basic of cases.
  //
  // See https://github.com/dart-lang/sdk/issues/27262 for the root issue which
  // will allow us to not rely on the naming schemes that dartdevc uses
  // internally, but instead specify our own.
  var appModuleScope = p.url
      .split(p
          .withoutExtension(p.relative(dartEntrypointId.path, from: moduleDir)))
      .join("__")
      .replaceAll('.', '\$46');
  var bootstrapContent = '''
require(["$appModulePath", "dart_sdk"], function(app, dart_sdk) {
  dart_sdk._isolate_helper.startRootIsolate(() => {}, []);
  app.$appModuleScope.main();
});
''';
  var bootstrapId = dartEntrypointId.addExtension('.bootstrap.js');
  transform.addOutput(new Asset.fromString(bootstrapId, bootstrapContent));

  var bootstrapModuleName = p.withoutExtension(
      p.relative(bootstrapId.path, from: p.dirname(dartEntrypointId.path)));
  var entrypointJsContent = '''
var el = document.createElement("script");
el.defer = true;
el.async = false;
el.src = "require.js";
el.setAttribute("data-main", "$bootstrapModuleName");
document.head.appendChild(el);
''';
  transform.addOutput(new Asset.fromString(
      dartEntrypointId.addExtension('.js'), entrypointJsContent));
  transform.addOutput(new Asset.fromString(
      dartEntrypointId.addExtension('.js.map'),
      '{"version":3,"sourceRoot":"","sources":[],"names":[],"mappings":"",'
      '"file":""}'));
}
