// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';

import 'package:collection/collection.dart';

import '../ascii_tree.dart' as tree;
import '../command.dart';
import '../command_runner.dart';
import '../entrypoint.dart';
import '../exceptions.dart';
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
  String get argumentsDescription => '[<package>...]';

  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-deps';

  @override
  bool get takesArguments => true;

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

    argParser.addFlag(
      'from-root',
      negatable: false,
      help:
          'Show paths from root packages down to the target packages '
          'instead of inverted.',
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
    final targetPackages = argResults.rest;

    if (targetPackages.isNotEmpty) {
      if (argResults.flag('json')) {
        usageException('Cannot combine --json and package arguments.');
      }
      if (argResults.flag('executables')) {
        usageException('Cannot combine --executables and package arguments.');
      }
      if (argResults.wasParsed('style') &&
          argResults.option('style') != 'tree') {
        usageException(
          'Cannot combine --style=${argResults.option('style')} and '
          'package arguments.',
        );
      }
      await _outputTargetPackages(buffer, targetPackages);
      log.message(buffer.toString());
      return;
    }

    if (argResults.flag('from-root')) {
      usageException('Cannot specify --from-root without target packages.');
    }

    if (argResults.flag('json')) {
      if (argResults.wasParsed('dev')) {
        usageException(
          'Cannot combine --json and --dev.\n'
          'The json output contains the dependency type in the output.',
        );
      }
      if (argResults.wasParsed('executables')) {
        usageException(
          'Cannot combine --json and --executables.\n'
          'The json output always lists available executables.',
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

      // Avoid polluting stdout when outputting json.
      final graph = await log.errorsOnlyUnlessTerminal(
        () async => await entrypoint.packageGraph,
      );

      while (toVisit.isNotEmpty) {
        final current = toVisit.removeLast();
        if (visited.contains(current)) continue;
        visited.add(current);
        final currentPackage =
            (await entrypoint.packageGraph).packages[current]!;
        final isRoot = workspacePackageNames.contains(currentPackage.name);
        final next =
            (isRoot
                    ? currentPackage.immediateDependencies
                    : currentPackage.dependencies)
                .keys
                .toList();
        final dependencyType = entrypoint.workspaceRoot.pubspec.dependencyType(
          current,
        );
        final kind =
            isRoot
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
          // This field is kept for backwards compatibility with dart 3.5 and
          // before. Clients should opt to consume directDependencies and
          // devDependencies separately instead.
          'dependencies':
              (isRoot
                      ? currentPackage.immediateDependencies
                      : currentPackage.dependencies)
                  .keys
                  .toList(),
          'directDependencies': currentPackage.dependencies.keys.toList(),
          if (isRoot)
            'devDependencies': currentPackage.devDependencies.keys.toList(),
          'dependencyConstraints': (isRoot
                  ? currentPackage.immediateDependencies
                  : currentPackage.dependencies)
              .map((k, v) => MapEntry(k, v.constraint.toString())),
        });
        toVisit.addAll(next);
      }
      final executables = [
        for (final package in [
          entrypoint.workspaceRoot,
          ...entrypoint.workspaceRoot.immediateDependencies.keys.map(
            (name) => graph.packages[name],
          ),
        ])
          ...package!.executableNames.map(
            (name) =>
                package == entrypoint.workspaceRoot
                    ? ':$name'
                    : (package.name == name ? name : '${package.name}:$name'),
          ),
      ];

      buffer.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'root': entrypoint.workspaceRoot.name,
          'packages': packagesJson,
          'sdks': [
            for (var sdk in sdks.values)
              if (sdk.version != null)
                {'name': sdk.name, 'version': sdk.version.toString()},
          ],
          'executables': executables,
        }),
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
  Future<void> _outputCompact(StringBuffer buffer) async {
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
    for (var name in names.sorted()) {
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
      transitive.sorted(),
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
  Future<void> _outputTree(StringBuffer buffer) async {
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
      immediateDependencies.removeAll(
        entrypoint.workspaceRoot.devDependencies.keys,
      );
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

  /// Outputs dependency paths explaining why [targets] are included.
  Future<void> _outputTargetPackages(
    StringBuffer buffer,
    List<String> targets,
  ) async {
    final graph = await entrypoint.packageGraph;
    final workspacePackageNames = {
      for (final p in entrypoint.workspaceRoot.transitiveWorkspace) p.name,
    };
    final reachableNames = {
      ...workspacePackageNames,
      ...await _getAllDependencies(),
    };

    for (final target in targets) {
      if (!graph.packages.containsKey(target)) {
        dataError('Package "$target" is not a dependency.');
      }
      if (!reachableNames.contains(target)) {
        dataError(
          'Package "$target" is only included via dev_dependencies. '
          'Run without --no-dev to see paths.',
        );
      }
    }

    for (final sdk in sdks.values) {
      if (!sdk.isAvailable) continue;
      buffer.writeln("${log.bold('${sdk.name} SDK')} ${sdk.version}");
    }

    if (argResults.flag('from-root')) {
      await _outputFromRootTree(
        buffer,
        targets,
        workspacePackageNames,
        reachableNames,
      );
    } else {
      await _outputInvertedTree(
        buffer,
        targets,
        workspacePackageNames,
        reachableNames,
      );
    }
  }

  /// Generates an inverted dependency tree starting from each package in
  /// [targets] and walking up to the workspace root packages.
  Future<void> _outputInvertedTree(
    StringBuffer buffer,
    List<String> targets,
    Set<String> workspacePackageNames,
    Set<String> reachableNames,
  ) async {
    final graph = await entrypoint.packageGraph;

    List<Package> dependeesOf(String targetName, {required bool isTargetRoot}) {
      if (!isTargetRoot && workspacePackageNames.contains(targetName)) {
        return const [];
      }
      final result = <Package>[];
      for (final name in reachableNames) {
        if (name == targetName) continue;
        final package = graph.packages[name]!;
        if (_childrenOf(package, workspacePackageNames).contains(targetName)) {
          result.add(package);
        }
      }
      result.sort((a, b) => a.name.compareTo(b.name));
      return result;
    }

    final packageTree = <String, Map>{};
    for (final targetName in targets) {
      final targetPackage = await _getPackage(targetName);
      final rootMap = <String, Map>{};
      packageTree[_labelPackage(targetPackage)] = rootMap;

      final toWalk = Queue<(Package, String, Map<String, Map>)>();
      final visited = <String>{targetPackage.name};

      for (final dependee in dependeesOf(
        targetPackage.name,
        isTargetRoot: true,
      )) {
        toWalk.add((dependee, targetPackage.name, rootMap));
      }

      while (toWalk.isNotEmpty) {
        final (package, dependedOn, map) = toWalk.removeFirst();
        final annotation = _edgeAnnotation(
          package,
          dependedOn,
          workspacePackageNames,
        );
        final nextDependees = dependeesOf(package.name, isTargetRoot: false);

        if (nextDependees.isNotEmpty && !visited.add(package.name)) {
          map['${log.gray('${package.name}...')} $annotation'] =
              <String, Map>{};
          continue;
        }

        final childMap = <String, Map>{};
        map['${_labelPackage(package)} $annotation'] = childMap;
        for (final dependee in nextDependees) {
          toWalk.add((dependee, package.name, childMap));
        }
      }
    }

    buffer.write(tree.fromMap(packageTree));
  }

  /// Generates a top-down dependency tree from workspace roots pruned to paths
  /// that reach [targets].
  Future<void> _outputFromRootTree(
    StringBuffer buffer,
    List<String> targets,
    Set<String> workspacePackageNames,
    Set<String> reachableNames,
  ) async {
    final graph = await entrypoint.packageGraph;
    final targetSet = targets.toSet();

    Set<String> ancestorsOfTarget(String target) {
      final ancestors = <String>{target};
      final queue = Queue<String>()..add(target);
      while (queue.isNotEmpty) {
        final current = queue.removeFirst();
        final isCurrentRoot = workspacePackageNames.contains(current);
        for (final name in reachableNames) {
          if (name == target) continue;
          if (isCurrentRoot && !workspacePackageNames.contains(name)) {
            continue;
          }
          final package = graph.packages[name]!;
          if (_childrenOf(package, workspacePackageNames).contains(current)) {
            if (ancestors.add(name)) {
              queue.add(name);
            }
          }
        }
      }
      return ancestors;
    }

    final ancestorsByTarget = {
      for (final target in targetSet) target: ancestorsOfTarget(target),
    };

    List<String> prunedChildrenOf(Package package) {
      final result = <String>[];
      for (final dep in _childrenOf(package, workspacePackageNames)) {
        if (!reachableNames.contains(dep)) continue;
        final reachesSomeTarget = targetSet.any(
          (target) =>
              package.name != target &&
              ancestorsByTarget[target]!.contains(dep),
        );
        if (reachesSomeTarget) {
          result.add(dep);
        }
      }
      return result;
    }

    final packageTree = <String, Map>{};
    final toWalk = Queue<(Package, String?, Map<String, Map>)>();
    final visited = <String>{};

    for (final name in workspacePackageNames) {
      final reachesOrIsTarget = targetSet.any(
        (target) => ancestorsByTarget[target]!.contains(name),
      );
      if (!reachesOrIsTarget) continue;
      toWalk.add((await _getPackage(name), null, packageTree));
    }

    while (toWalk.isNotEmpty) {
      final (package, parentName, map) = toWalk.removeFirst();
      final annotation =
          parentName == null
              ? null
              : _edgeAnnotation(
                graph.packages[parentName]!,
                package.name,
                workspacePackageNames,
              );
      final labelSuffix = annotation == null ? '' : ' $annotation';
      final children = prunedChildrenOf(package);

      if (children.isNotEmpty && !visited.add(package.name)) {
        map['${log.gray('${package.name}...')}$labelSuffix'] = <String, Map>{};
        continue;
      }

      final childMap = <String, Map>{};
      map['${_labelPackage(package)}$labelSuffix'] = childMap;
      for (final dep in children) {
        toWalk.add((await _getPackage(dep), package.name, childMap));
      }
    }

    buffer.write(tree.fromMap(packageTree));
  }

  Iterable<String> _childrenOf(
    Package package,
    Set<String> workspacePackageNames,
  ) {
    if (!workspacePackageNames.contains(package.name)) {
      return package.dependencies.keys;
    }
    return {
      ...package.dependencies.keys,
      if (_includeDev) ...package.devDependencies.keys,
      ...package.pubspec.dependencyOverrides.keys,
    };
  }

  String _edgeAnnotation(
    Package parent,
    String childName,
    Set<String> workspacePackageNames,
  ) {
    if (!workspacePackageNames.contains(parent.name)) {
      final dep = parent.dependencies[childName]!;
      return log.gray('(${dep.constraint})');
    }
    final dep = parent.dependencies[childName];
    final devDep = _includeDev ? parent.devDependencies[childName] : null;
    final overrideDep = parent.pubspec.dependencyOverrides[childName];
    final parts = <String>[
      if (dep != null)
        '${dep.constraint}'
      else if (devDep != null)
        '${devDep.constraint}, dev',
      if (overrideDep != null) 'override: ${overrideDep.constraint}',
    ];
    return log.gray('(${parts.join(', ')})');
  }

  /// Gets the names of the non-immediate dependencies of the workspace
  /// packages.
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
        .expand(
          (p) => graph.transitiveDependencies(
            p,
            followDevDependenciesFromPackage: false,
          ),
        )
        .map((package) => package.name)
        .toSet();
  }

  /// Get the package named [name], or throw a [DataException] if it's not
  /// available.
  ///
  /// It's very unlikely that the lockfile won't be up-to-date with the pubspec,
  /// but it's possible, since [Entrypoint.ensureUpToDate]'s modification time
  /// check can return a false negative. This fails gracefully if that happens.
  Future<Package> _getPackage(String name) async {
    final package = (await entrypoint.packageGraph).packages[name];
    if (package != null) return package;
    dataError(
      'The pubspec.yaml file has changed since the pubspec.lock file '
      'was generated, please run "$topLevelProgram pub get" again.',
    );
  }

  /// Outputs all executables reachable from [entrypoint].
  Future<void> _outputExecutables(StringBuffer buffer) async {
    final graph = await entrypoint.packageGraph;
    final packages = {
      for (final p in entrypoint.workspaceRoot.transitiveWorkspace) ...[
        graph.packages[p.name]!,
        ...(_includeDev ? p.immediateDependencies : p.dependencies).keys.map(
          (name) => graph.packages[name]!,
        ),
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
