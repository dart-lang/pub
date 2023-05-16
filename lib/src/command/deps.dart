// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';

import '../ascii_tree.dart' as tree;
import '../command.dart';
import '../command_runner.dart';
import '../log.dart' as log;
import '../package.dart';
import '../pubspec.dart';
import '../sdk.dart';
import '../utils.dart';

/// Handles the `deps` pub command.
class DepsCommand extends PubCommand {
  @override
  String get name => 'deps';

  @override
  String get description => 'Print package dependencies.';

  @override
  String get argumentsDescription => '[arguments...]';

  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-deps';

  @override
  bool get takesArguments => false;

  /// Whether to include dev dependencies.
  bool get _includeDev => asBool(argResults['dev']);

  DepsCommand() {
    argParser.addOption(
      'style',
      abbr: 's',
      help: 'How output should be displayed.',
      allowed: ['compact', 'tree', 'list'],
      defaultsTo: 'tree',
    );

    argParser.addFlag(
      'dev',
      help: 'Whether to include dev dependencies.',
      defaultsTo: true,
    );

    argParser.addFlag(
      'executables',
      negatable: false,
      help: 'List all available executables.',
    );

    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Output dependency information in a json format.',
    );

    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
  }

  @override
  Future<void> runProtected() async {
    // Explicitly Run this in the directorycase we don't access `entrypoint.packageGraph`.
    await entrypoint.ensureUpToDate();
    final buffer = StringBuffer();

    if (asBool(argResults['json'])) {
      if (argResults.wasParsed('dev')) {
        usageException(
          'Cannot combine --json and --dev.\nThe json output contains the dependency type in the output.',
        );
      }
      if (argResults.wasParsed('executables')) {
        usageException(
          'Cannot combine --json and --executables.\nThe json output always lists available executables.',
        );
      }
      if (argResults.wasParsed('style')) {
        usageException('Cannot combine --json and --style.');
      }
      await entrypoint.ensureUpToDate();
      final visited = <String>[];
      final toVisit = [entrypoint.root.name];
      final packagesJson = <dynamic>[];
      while (toVisit.isNotEmpty) {
        final current = toVisit.removeLast();
        if (visited.contains(current)) continue;
        visited.add(current);
        final currentPackage = entrypoint.packageGraph.packages[current]!;
        final next = (current == entrypoint.root.name
                ? entrypoint.root.immediateDependencies
                : currentPackage.dependencies)
            .keys
            .toList();
        final dependencyType = entrypoint.root.pubspec.dependencyType(current);
        final kind = currentPackage == entrypoint.root
            ? 'root'
            : (dependencyType == DependencyType.direct
                ? 'direct'
                : (dependencyType == DependencyType.dev
                    ? 'dev'
                    : 'transitive'));
        final source =
            entrypoint.lockFile.packages[current]?.source.name ?? 'root';
        packagesJson.add({
          'name': current,
          'version': currentPackage.version.toString(),
          'kind': kind,
          'source': source,
          'dependencies': next
        });
        toVisit.addAll(next);
      }
      var executables = [
        for (final package in [
          entrypoint.root,
          ...entrypoint.root.immediateDependencies.keys
              .map((name) => entrypoint.packageGraph.packages[name])
        ])
          ...package!.executableNames.map(
            (name) => package == entrypoint.root
                ? ':$name'
                : (package.name == name ? name : '${package.name}:$name'),
          )
      ];

      buffer.writeln(
        JsonEncoder.withIndent('  ').convert(
          {
            'root': entrypoint.root.name,
            'packages': packagesJson,
            'sdks': [
              for (var sdk in sdks.values)
                if (sdk.version != null)
                  {'name': sdk.name, 'version': sdk.version.toString()}
            ],
            'executables': executables
          },
        ),
      );
    } else {
      if (asBool(argResults['executables'])) {
        _outputExecutables(buffer);
      } else {
        for (var sdk in sdks.values) {
          if (!sdk.isAvailable) continue;
          buffer.writeln("${log.bold('${sdk.name} SDK')} ${sdk.version}");
        }

        buffer.writeln(_labelPackage(entrypoint.root));

        switch (argResults['style']) {
          case 'compact':
            _outputCompact(buffer);
            break;
          case 'list':
            _outputList(buffer);
            break;
          case 'tree':
            _outputTree(buffer);
            break;
        }
      }
    }

    log.message(buffer);
  }

  /// Outputs a list of all of the package's immediate, dev, override, and
  /// transitive dependencies.
  ///
  /// For each dependency listed, *that* package's immediate dependencies are
  /// shown. Unlike [_outputList], this prints all of these dependencies on one
  /// line.
  void _outputCompact(
    StringBuffer buffer,
  ) {
    var root = entrypoint.root;
    _outputCompactPackages('dependencies', root.dependencies.keys, buffer);
    if (_includeDev) {
      _outputCompactPackages(
        'dev dependencies',
        root.devDependencies.keys,
        buffer,
      );
    }
    _outputCompactPackages(
      'dependency overrides',
      root.dependencyOverrides.keys,
      buffer,
    );

    var transitive = _getTransitiveDependencies();
    _outputCompactPackages('transitive dependencies', transitive, buffer);
  }

  /// Outputs one section of packages in the compact output.
  void _outputCompactPackages(
    String section,
    Iterable<String> names,
    StringBuffer buffer,
  ) {
    if (names.isEmpty) return;

    buffer.writeln();
    buffer.writeln('$section:');
    for (var name in ordered(names)) {
      var package = _getPackage(name);

      buffer.write('- ${_labelPackage(package)}');
      if (package.dependencies.isEmpty) {
        buffer.writeln();
      } else {
        var depNames = package.dependencies.keys;
        var depsList = "[${depNames.join(' ')}]";
        buffer.writeln(' ${log.gray(depsList)}');
      }
    }
  }

  /// Outputs a list of all of the package's immediate, dev, override, and
  /// transitive dependencies.
  ///
  /// For each dependency listed, *that* package's immediate dependencies are
  /// shown.
  void _outputList(StringBuffer buffer) {
    var root = entrypoint.root;
    _outputListSection('dependencies', root.dependencies.keys, buffer);
    if (_includeDev) {
      _outputListSection('dev dependencies', root.devDependencies.keys, buffer);
    }
    _outputListSection(
      'dependency overrides',
      root.dependencyOverrides.keys,
      buffer,
    );

    var transitive = _getTransitiveDependencies();
    if (transitive.isEmpty) return;

    _outputListSection('transitive dependencies', ordered(transitive), buffer);
  }

  /// Outputs one section of packages in the list output.
  void _outputListSection(
    String name,
    Iterable<String> deps,
    StringBuffer buffer,
  ) {
    if (deps.isEmpty) return;

    buffer.writeln();
    buffer.writeln('$name:');

    for (var name in deps) {
      var package = _getPackage(name);
      buffer.writeln('- ${_labelPackage(package)}');

      for (var dep in package.dependencies.values) {
        buffer.writeln('  - ${log.bold(dep.name)} ${log.gray(dep.constraint)}');
      }
    }
  }

  /// Generates a dependency tree for the root package.
  ///
  /// If a package is encountered more than once (i.e. a shared or circular
  /// dependency), later ones are not traversed. This is done in breadth-first
  /// fashion so that a package will always be expanded at the shallowest
  /// depth that it appears at.
  void _outputTree(
    StringBuffer buffer,
  ) {
    // The work list for the breadth-first traversal. It contains the package
    // being added to the tree, and the parent map that will receive that
    // package.
    var toWalk = Queue<Pair<Package, Map<String, Map>>>();
    var visited = <String>{entrypoint.root.name};

    // Start with the root dependencies.
    var packageTree = <String, Map>{};
    var immediateDependencies =
        entrypoint.root.immediateDependencies.keys.toSet();
    if (!_includeDev) {
      immediateDependencies.removeAll(entrypoint.root.devDependencies.keys);
    }
    for (var name in immediateDependencies) {
      toWalk.add(Pair(_getPackage(name), packageTree));
    }

    // Do a breadth-first walk to the dependency graph.
    while (toWalk.isNotEmpty) {
      var pair = toWalk.removeFirst();
      var package = pair.first;
      var map = pair.last;

      if (visited.contains(package.name)) {
        map[log.gray('${package.name}...')] = <String, Map>{};
        continue;
      }

      visited.add(package.name);

      // Populate the map with this package's dependencies.
      var childMap = <String, Map>{};
      map[_labelPackage(package)] = childMap;

      for (var dep in package.dependencies.values) {
        toWalk.add(Pair(_getPackage(dep.name), childMap));
      }
    }

    buffer.write(tree.fromMap(packageTree));
  }

  String _labelPackage(Package package) =>
      '${log.bold(package.name)} ${package.version}';

  /// Gets the names of the non-immediate dependencies of the root package.
  Set<String> _getTransitiveDependencies() {
    var transitive = _getAllDependencies();
    var root = entrypoint.root;
    transitive.remove(root.name);
    transitive.removeAll(root.dependencies.keys);
    if (_includeDev) {
      transitive.removeAll(root.devDependencies.keys);
    }
    transitive.removeAll(root.dependencyOverrides.keys);
    return transitive;
  }

  Set<String> _getAllDependencies() {
    if (_includeDev) return entrypoint.packageGraph.packages.keys.toSet();

    var nonDevDependencies = entrypoint.root.dependencies.keys.toList()
      ..addAll(entrypoint.root.dependencyOverrides.keys);
    return nonDevDependencies
        .expand((name) => entrypoint.packageGraph.transitiveDependencies(name))
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
        'was generated, please run "$topLevelProgram pub get" again.');
  }

  /// Outputs all executables reachable from [entrypoint].
  void _outputExecutables(StringBuffer buffer) {
    var packages = [
      entrypoint.root,
      ...(_includeDev
              ? entrypoint.root.immediateDependencies
              : entrypoint.root.dependencies)
          .keys
          .map((name) => entrypoint.packageGraph.packages[name]!)
    ];

    for (var package in packages) {
      var executables = package.executableNames;
      if (executables.isNotEmpty) {
        buffer.writeln(_formatExecutables(package.name, executables.toList()));
      }
    }
  }

  /// Returns formatted string that lists [executables] for the [packageName].
  /// Examples:
  ///
  ///     _formatExecutables('foo', ['foo'])        // -> 'foo'
  ///     _formatExecutables('foo', ['bar'])        // -> 'foo:bar'
  ///     _formatExecutables('foo', ['bar', 'foo']) // -> 'foo: foo, bar'
  ///
  /// Note the leading space before first executable and sorting order in the
  /// last example.
  String _formatExecutables(String packageName, List<String> executables) {
    if (executables.length == 1) {
      // If executable matches the package name omit the name of executable in
      // the output.
      return executables.first != packageName
          ? '$packageName:${log.bold(executables.first)}'
          : log.bold(executables.first);
    }

    // Sort executables to make executable that matches the package name to be
    // the first in the list.
    executables.sort((e1, e2) {
      if (e1 == packageName) {
        return -1;
      } else if (e2 == packageName) {
        return 1;
      } else {
        return e1.compareTo(e2);
      }
    });

    return '$packageName: ${executables.map(log.bold).join(', ')}';
  }
}
