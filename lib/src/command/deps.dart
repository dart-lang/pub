// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';

import '../ascii_tree.dart' as tree;
import '../command.dart';
import '../command_runner.dart';
import '../entrypoint.dart';
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
  bool get _includeDev => argResults.flag('dev');

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
    final buffer = StringBuffer();

    if (argResults.flag('json')) {
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
      final visited = <String>[];
      final workspacePackageNames = [
        ...entrypoint.workspaceRoot.transitiveWorkspace.map((p) => p.name),
      ];
      final toVisit = [...workspacePackageNames];
      final packagesJson = <dynamic>[];
      final graph = await entrypoint.packageGraph;
      while (toVisit.isNotEmpty) {
        final current = toVisit.removeLast();
        if (visited.contains(current)) continue;
        visited.add(current);
        final currentPackage =
            (await entrypoint.packageGraph).packages[current]!;
        final isRoot = workspacePackageNames.contains(currentPackage.name);
        final next = (isRoot
                ? currentPackage.immediateDependencies
                : currentPackage.dependencies)
            .keys
            .toList();
        final dependencyType =
            entrypoint.workspaceRoot.pubspec.dependencyType(current);
        final kind = isRoot
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
          'dependencies': next,
        });
        toVisit.addAll(next);
      }
      final executables = [
        for (final package in [
          entrypoint.workspaceRoot,
          ...entrypoint.workspaceRoot.immediateDependencies.keys
              .map((name) => graph.packages[name]),
        ])
          ...package!.executableNames.map(
            (name) => package == entrypoint.workspaceRoot
                ? ':$name'
                : (package.name == name ? name : '${package.name}:$name'),
          ),
      ];

      buffer.writeln(
        JsonEncoder.withIndent('  ').convert(
          {
            'root': entrypoint.workspaceRoot.name,
            'packages': packagesJson,
            'sdks': [
              for (var sdk in sdks.values)
                if (sdk.version != null)
                  {'name': sdk.name, 'version': sdk.version.toString()},
            ],
            'executables': executables,
          },
        ),
      );
    } else {
      if (argResults.flag('executables')) {
        await _outputExecutables(buffer);
      } else {
        for (var sdk in sdks.values) {
          if (!sdk.isAvailable) continue;
          buffer.writeln("${log.bold('${sdk.name} SDK')} ${sdk.version}");
        }

        switch (argResults.optionWithDefault('style')) {
          case 'compact':
            await _outputCompact(buffer);
            break;
          case 'list':
            await _outputList(buffer);
            break;
          case 'tree':
            await _outputTree(buffer);
            break;
        }
      }
    }

    log.message(buffer.toString());
  }

  /// Outputs a list of all of the package's immediate, dev, override, and
  /// transitive dependencies.
  ///
  /// For each dependency listed, *that* package's immediate dependencies are
  /// shown. Unlike [_outputList], this prints all of these dependencies on one
  /// line.
  Future<void> _outputCompact(
    StringBuffer buffer,
  ) async {
    var first = true;
    for (final root in entrypoint.workspaceRoot.transitiveWorkspace) {
      if (!first) {
        buffer.write('\n');
      }
      first = false;

      buffer.writeln(_labelPackage(root));
      await _outputCompactPackages(
        'dependencies',
        root.dependencies.keys,
        buffer,
      );
      if (_includeDev) {
        await _outputCompactPackages(
          'dev dependencies',
          root.devDependencies.keys,
          buffer,
        );
      }
      await _outputCompactPackages(
        'dependency overrides',
        root.pubspec.dependencyOverrides.keys,
        buffer,
      );
    }

    final transitive = await _getTransitiveDependencies();
    await _outputCompactPackages('transitive dependencies', transitive, buffer);
  }

  /// Outputs one section of packages in the compact output.
  Future<void> _outputCompactPackages(
    String section,
    Iterable<String> names,
    StringBuffer buffer,
  ) async {
    if (names.isEmpty) return;

    buffer.writeln();
    buffer.writeln('$section:');
    for (var name in ordered(names)) {
      final package = await _getPackage(name);

      buffer.write('- ${_labelPackage(package)}');
      if (package.dependencies.isEmpty) {
        buffer.writeln();
      } else {
        final depNames = package.dependencies.keys;
        final depsList = "[${depNames.join(' ')}]";
        buffer.writeln(' ${log.gray(depsList)}');
      }
    }
  }

  /// Outputs a list of all of the package's immediate, dev, override, and
  /// transitive dependencies.
  ///
  /// For each dependency listed, *that* package's immediate dependencies are
  /// shown.
  Future<void> _outputList(StringBuffer buffer) async {
    var first = true;
    for (final root in entrypoint.workspaceRoot.transitiveWorkspace) {
      if (!first) {
        buffer.write('\n');
      }
      first = false;

      buffer.writeln(_labelPackage(root));
      await _outputListSection('dependencies', root.dependencies.keys, buffer);
      if (_includeDev) {
        await _outputListSection(
          'dev dependencies',
          root.devDependencies.keys,
          buffer,
        );
      }
      await _outputListSection(
        'dependency overrides',
        root.pubspec.dependencyOverrides.keys,
        buffer,
      );
    }

    final transitive = await _getTransitiveDependencies();
    if (transitive.isEmpty) return;

    await _outputListSection(
      'transitive dependencies',
      ordered(transitive),
      buffer,
    );
  }

  /// Outputs one section of packages in the list output.
  Future<void> _outputListSection(
    String name,
    Iterable<String> deps,
    StringBuffer buffer,
  ) async {
    if (deps.isEmpty) return;

    buffer.writeln();
    buffer.writeln('$name:');

    for (var name in deps) {
      final package = await _getPackage(name);
      buffer.writeln('- ${_labelPackage(package)}');

      for (var dep in package.dependencies.values) {
        buffer.writeln(
          '  - ${log.bold(dep.name)} ${log.gray(dep.constraint.toString())}',
        );
      }
    }
  }

  /// Generates a dependency tree for the root package.
  ///
  /// If a package is encountered more than once (i.e. a shared or circular
  /// dependency), later ones are not traversed. This is done in breadth-first
  /// fashion so that a package will always be expanded at the shallowest
  /// depth that it appears at.
  Future<void> _outputTree(
    StringBuffer buffer,
  ) async {
    // The work list for the breadth-first traversal. It contains the package
    // being added to the tree, and the parent map that will receive that
    // package.
    final toWalk = Queue<(Package, Map<String, Map>)>();
    final visited = <String>{};

    // Start with the root dependencies.
    final packageTree = <String, Map>{};
    final workspacePackageNames = [
      ...entrypoint.workspaceRoot.transitiveWorkspace.map((p) => p.name),
    ];
    final immediateDependencies =
        entrypoint.workspaceRoot.immediateDependencies.keys.toSet();
    if (!_includeDev) {
      immediateDependencies
          .removeAll(entrypoint.workspaceRoot.devDependencies.keys);
    }
    for (var name in workspacePackageNames) {
      toWalk.add((await _getPackage(name), packageTree));
    }

    // Do a breadth-first walk to the dependency graph.
    while (toWalk.isNotEmpty) {
      final (package, map) = toWalk.removeFirst();

      if (!visited.add(package.name)) {
        map[log.gray('${package.name}...')] = <String, Map>{};
        continue;
      }

      // Populate the map with this package's dependencies.
      final childMap = <String, Map>{};
      map[_labelPackage(package)] = childMap;

      final isRoot = workspacePackageNames.contains(package.name);
      final children = [
        ...isRoot
            ? package.immediateDependencies.keys
            : package.dependencies.keys,
      ];
      if (!_includeDev) {
        children.removeWhere(package.devDependencies.keys.contains);
      }
      for (var dep in children) {
        toWalk.add((await _getPackage(dep), childMap));
      }
    }
    buffer.write(tree.fromMap(packageTree));
  }

  String _labelPackage(Package package) =>
      '${log.bold(package.name)} ${package.version}';

  /// Gets the names of the non-immediate dependencies of the workspace packages.
  Future<Set<String>> _getTransitiveDependencies() async {
    final transitive = await _getAllDependencies();
    for (final root in entrypoint.workspaceRoot.transitiveWorkspace) {
      transitive.remove(root.name);
      transitive.removeAll(root.dependencies.keys);
      if (_includeDev) {
        transitive.removeAll(root.devDependencies.keys);
      }
      transitive.removeAll(root.pubspec.dependencyOverrides.keys);
    }
    return transitive;
  }

  Future<Set<String>> _getAllDependencies() async {
    final graph = await entrypoint.packageGraph;
    if (_includeDev) {
      return graph.packages.keys.toSet();
    }

    final nonDevDependencies = [
      for (final package in entrypoint.workspaceRoot.transitiveWorkspace) ...[
        ...package.dependencies.keys,
        ...package.pubspec.dependencyOverrides.keys,
      ],
    ];
    return nonDevDependencies
        .expand(graph.transitiveDependencies)
        .map((package) => package.name)
        .toSet();
  }

  /// Get the package named [name], or throw a [DataError] if it's not
  /// available.
  ///
  /// It's very unlikely that the lockfile won't be up-to-date with the pubspec,
  /// but it's possible, since [Entrypoint.assertUpToDate]'s modification time
  /// check can return a false negative. This fails gracefully if that happens.
  Future<Package> _getPackage(String name) async {
    final package = (await entrypoint.packageGraph).packages[name];
    if (package != null) return package;
    dataError('The pubspec.yaml file has changed since the pubspec.lock file '
        'was generated, please run "$topLevelProgram pub get" again.');
  }

  /// Outputs all executables reachable from [entrypoint].
  Future<void> _outputExecutables(StringBuffer buffer) async {
    final graph = await entrypoint.packageGraph;
    final packages = {
      for (final p in entrypoint.workspaceRoot.transitiveWorkspace) ...[
        graph.packages[p.name]!,
        ...(_includeDev ? p.immediateDependencies : p.dependencies)
            .keys
            .map((name) => graph.packages[name]!),
      ],
    };

    for (var package in packages) {
      final executables = package.executableNames;
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
