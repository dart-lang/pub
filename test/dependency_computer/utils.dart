// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;
import 'package:pub/src/barback/cycle_exception.dart';
import 'package:pub/src/barback/dependency_computer.dart';
import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/package.dart';
import 'package:pub/src/package_graph.dart';
import 'package:pub/src/system_cache.dart';
import 'package:pub/src/utils.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../test_pub.dart';

/// Expects that [DependencyComputer.transformersNeededByTransformers] will
/// return a graph matching [expected] when run on the package graph defined by
/// packages in the sandbox.
void expectDependencies(Map<String, Iterable<String>> expected) {
  expected = mapMap(expected, value: (_, ids) => ids.toSet());

  schedule(() {
    var computer = new DependencyComputer(_loadPackageGraph());
    var result = mapMap(
        computer.transformersNeededByTransformers(),
        key: (id, _) => id.toString(),
        value: (_, ids) => ids.map((id) => id.toString()).toSet());
    expect(result, equals(expected));
  }, "expect dependencies to match $expected");
}

/// Expects that [computeTransformersNeededByTransformers] will throw an
/// exception matching [matcher] when run on the package graph defiend by
/// packages in the sandbox.
void expectException(matcher) {
  schedule(() {
    expect(() {
      var computer = new DependencyComputer(_loadPackageGraph());
      computer.transformersNeededByTransformers();
    }, throwsA(matcher));
  }, "expect an exception: $matcher");
}

/// Expects that [computeTransformersNeededByTransformers] will throw a
/// [CycleException] with the given [steps] when run on the package graph
/// defiend by packages in the sandbox.
void expectCycleException(Iterable<String> steps) {
  expectException(predicate((error) {
    expect(error, new isInstanceOf<CycleException>());
    expect(error.steps, equals(steps));
    return true;
  }, "cycle exception:\n${steps.map((step) => "  $step").join("\n")}"));
}

/// Expects that [DependencyComputer.transformersNeededByLibrary] will return
/// transformer ids matching [expected] when run on the library identified by
/// [id].
void expectLibraryDependencies(String id, Iterable<String> expected) {
  expected = expected.toSet();

  schedule(() {
    var computer = new DependencyComputer(_loadPackageGraph());
    var result = computer.transformersNeededByLibrary(new AssetId.parse(id))
        .map((id) => id.toString()).toSet();
    expect(result, equals(expected));
  }, "expect dependencies to match $expected");
}

/// Loads a [PackageGraph] from the packages in the sandbox.
///
/// This graph will also include barback and its transitive dependencies from
/// the repo.
PackageGraph _loadPackageGraph() {
  // Load the sandbox packages.
  var packages = {};

  var systemCache = new SystemCache(rootDir: p.join(sandboxDir, cachePath));
  systemCache.sources.setDefault('path');
  var entrypoint = new Entrypoint(p.join(sandboxDir, appPath), systemCache);

  for (var package in listDir(sandboxDir)) {
    if (!fileExists(p.join(package, 'pubspec.yaml'))) continue;
    var packageName = p.basename(package);
    packages[packageName] = new Package.load(
        packageName, package, systemCache.sources);
  }

  loadPackage(packageName) {
    if (packages.containsKey(packageName)) return;
    packages[packageName] = new Package.load(
        packageName, packagePath(packageName), systemCache.sources);
    for (var dep in packages[packageName].dependencies) {
      loadPackage(dep.name);
    }
  }

  loadPackage('barback');

  return new PackageGraph(entrypoint, null, packages);
}

/// Returns the contents of a no-op transformer that imports each URL in
/// [imports].
String transformer([Iterable<String> imports]) {
  if (imports == null) imports = [];

  var buffer = new StringBuffer()
      ..writeln('import "package:barback/barback.dart";');
  for (var import in imports) {
    buffer.writeln('import "$import";');
  }

  buffer.writeln("""
NoOpTransformer extends Transformer {
  bool isPrimary(AssetId id) => true;
  void apply(Transform transform) {}
}
""");

  return buffer.toString();
}
