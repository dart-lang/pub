// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import '../ascii_tree.dart' as tree;
import '../command.dart';
import '../log.dart' as log;
import '../package.dart';
import '../utils.dart';

/// Handles the `deps` pub command.
class DepsCommand extends PubCommand {
  String get name => "deps";
  String get description => "Print package dependencies.";
  List<String> get aliases => const ["dependencies", "tab"];
  String get invocation => "pub deps";
  String get docUrl => "http://dartlang.org/tools/pub/cmd/pub-deps.html";
  bool get takesArguments => false;

  /// The [StringBuffer] used to accumulate the output.
  StringBuffer _buffer;

  /// Whether to include dev dependencies.
  bool get _includeDev => argResults['dev'];

  DepsCommand() {
    argParser.addOption("style",
        abbr: "s",
        help: "How output should be displayed.",
        allowed: ["compact", "tree", "list"],
        defaultsTo: "tree");

    argParser.addFlag("dev",
        negatable: true,
        help: "Whether to include dev dependencies.",
        defaultsTo: true);
  }

  void run() {
    // Explicitly run this in case we don't access `entrypoint.packageGraph`.
    entrypoint.assertUpToDate();

    _buffer = new StringBuffer();

    _buffer.writeln(_labelPackage(entrypoint.root));

    switch (argResults["style"]) {
      case "compact":
        _outputCompact();
        break;
      case "list":
        _outputList();
        break;
      case "tree":
        _outputTree();
        break;
    }

    log.message(_buffer);
  }

  /// Outputs a list of all of the package's immediate, dev, override, and
  /// transitive dependencies.
  ///
  /// For each dependency listed, *that* package's immediate dependencies are
  /// shown. Unlike [_outputList], this prints all of these dependencies on one
  /// line.
  void _outputCompact() {
    var root = entrypoint.root;
    _outputCompactPackages(
        "dependencies", root.dependencies.map((dep) => dep.name));
    if (_includeDev) {
      _outputCompactPackages(
          "dev dependencies", root.devDependencies.map((dep) => dep.name));
    }
    _outputCompactPackages("dependency overrides",
        root.dependencyOverrides.map((dep) => dep.name));

    var transitive = _getTransitiveDependencies();
    _outputCompactPackages("transitive dependencies", transitive);
  }

  /// Outputs one section of packages in the compact output.
  _outputCompactPackages(String section, Iterable<String> names) {
    if (names.isEmpty) return;

    _buffer.writeln();
    _buffer.writeln("$section:");
    for (var name in ordered(names)) {
      var package = _getPackage(name);

      _buffer.write("- ${_labelPackage(package)}");
      if (package.dependencies.isEmpty) {
        _buffer.writeln();
      } else {
        var depNames = package.dependencies.map((dep) => dep.name);
        var depsList = "[${depNames.join(' ')}]";
        _buffer.writeln(" ${log.gray(depsList)}");
      }
    }
  }

  /// Outputs a list of all of the package's immediate, dev, override, and
  /// transitive dependencies.
  ///
  /// For each dependency listed, *that* package's immediate dependencies are
  /// shown.
  void _outputList() {
    var root = entrypoint.root;
    _outputListSection(
        "dependencies", root.dependencies.map((dep) => dep.name));
    if (_includeDev) {
      _outputListSection(
          "dev dependencies", root.devDependencies.map((dep) => dep.name));
    }
    _outputListSection("dependency overrides",
        root.dependencyOverrides.map((dep) => dep.name));

    var transitive = _getTransitiveDependencies();
    if (transitive.isEmpty) return;

    _outputListSection("transitive dependencies", ordered(transitive));
  }

  /// Outputs one section of packages in the list output.
  _outputListSection(String name, Iterable<String> deps) {
    if (deps.isEmpty) return;

    _buffer.writeln();
    _buffer.writeln("$name:");

    for (var name in deps) {
      var package = _getPackage(name);
      _buffer.writeln("- ${_labelPackage(package)}");

      for (var dep in package.dependencies) {
        _buffer
            .writeln("  - ${log.bold(dep.name)} ${log.gray(dep.constraint)}");
      }
    }
  }

  /// Generates a dependency tree for the root package.
  ///
  /// If a package is encountered more than once (i.e. a shared or circular
  /// dependency), later ones are not traversed. This is done in breadth-first
  /// fashion so that a package will always be expanded at the shallowest
  /// depth that it appears at.
  void _outputTree() {
    // The work list for the breadth-first traversal. It contains the package
    // being added to the tree, and the parent map that will receive that
    // package.
    var toWalk = new Queue<Pair<Package, Map<String, Map>>>();
    var visited = new Set<String>.from([entrypoint.root.name]);

    // Start with the root dependencies.
    var packageTree = <String, Map>{};
    var immediateDependencies = entrypoint.root.immediateDependencies.toSet();
    if (!_includeDev) {
      immediateDependencies.removeAll(entrypoint.root.devDependencies);
    }
    for (var dep in immediateDependencies) {
      toWalk.add(new Pair(_getPackage(dep.name), packageTree));
    }

    // Do a breadth-first walk to the dependency graph.
    while (toWalk.isNotEmpty) {
      var pair = toWalk.removeFirst();
      var package = pair.first;
      var map = pair.last;

      if (visited.contains(package.name)) {
        map[log.gray('${package.name}...')] = {};
        continue;
      }

      visited.add(package.name);

      // Populate the map with this package's dependencies.
      var childMap = <String, Map>{};
      map[_labelPackage(package)] = childMap;

      for (var dep in package.dependencies) {
        toWalk.add(new Pair(_getPackage(dep.name), childMap));
      }
    }

    _buffer.write(tree.fromMap(packageTree, showAllChildren: true));
  }

  String _labelPackage(Package package) =>
      "${log.bold(package.name)} ${package.version}";

  /// Gets the names of the non-immediate dependencies of the root package.
  Set<String> _getTransitiveDependencies() {
    var transitive = _getAllDependencies();
    var root = entrypoint.root;
    transitive.remove(root.name);
    transitive.removeAll(root.dependencies.map((dep) => dep.name));
    if (_includeDev) {
      transitive.removeAll(root.devDependencies.map((dep) => dep.name));
    }
    transitive.removeAll(root.dependencyOverrides.map((dep) => dep.name));
    return transitive;
  }

  Set<String> _getAllDependencies() {
    if (_includeDev) return entrypoint.packageGraph.packages.keys.toSet();

    var nonDevDependencies = entrypoint.root.dependencies.toList()
      ..addAll(entrypoint.root.dependencyOverrides);
    return nonDevDependencies
        .expand(
            (dep) => entrypoint.packageGraph.transitiveDependencies(dep.name))
        .map((package) => package.name)
        .toSet();
  }

  /// Get the package named [name], or throw a [DataError] if it's not
  /// available.
  ///
  /// It's very unlikely that the lockfile won't be up-to-date with the pubspec,
  /// but it's possible, since [Entrypoint.assertUpToDate]'s modification time
  /// check can return a false negative. This fails gracefully if that happens.
  Package _getPackage(String name) {
    var package = entrypoint.packageGraph.packages[name];
    if (package != null) return package;
    dataError('The pubspec.yaml file has changed since the pubspec.lock file '
        'was generated, please run "pub get" again.');
    return null;
  }
}
