// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../io.dart';
import '../log.dart' as log;
import '../pubspec.dart';
import '../solver.dart';
import '../utils.dart';

/// Handles the `remove` pub command. Removes dependencies from `pubspec.yaml`,
/// and performs an operation similar to `pub get`. Unlike `pub add`, this
/// command supports the removal of multiple dependencies.
class RemoveCommand extends PubCommand {
  @override
  String get name => 'remove';
  @override
  String get description => '''
Removes dependencies from `pubspec.yaml`.

Invoking `dart pub remove foo bar` will remove `foo` and `bar` from either
`dependencies` or `dev_dependencies` in `pubspec.yaml`.

To remove a dependency override of a package prefix the package name with
'override:'.
''';

  @override
  String get argumentsDescription => '<package1> [<package2>...]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-remove';
  @override
  bool get isOffline => asBool(argResults['offline']);

  bool get isDryRun => asBool(argResults['dry-run']);

  RemoveCommand() {
    argParser.addFlag(
      'offline',
      help: 'Use cached packages instead of accessing the network.',
    );

    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: "Report what dependencies would change but don't change any.",
    );

    argParser.addFlag(
      'precompile',
      help: 'Precompile executables in immediate dependencies.',
    );

    argParser.addFlag(
      'example',
      defaultsTo: true,
      help: 'Also update dependencies in `example/` (if it exists).',
      hide: true,
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
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be removed.');
    }

    final targets = Set<String>.from(argResults.rest).map((descriptor) {
      final isOverride = descriptor.startsWith('override:');
      final name =
          isOverride ? descriptor.substring('override:'.length) : descriptor;
      return _PackageRemoval(name, removeFromOverride: isOverride);
    });

    if (!isDryRun) {
      /// Update the pubspec.
      _writeRemovalToPubspec(targets);
    }
    final rootPubspec = entrypoint.root.pubspec;
    final newPubspec = _removePackagesFromPubspec(rootPubspec, targets);

    await entrypoint.withPubspec(newPubspec).acquireDependencies(
          SolveType.get,
          precompile: !isDryRun && asBool(argResults['precompile']),
          dryRun: isDryRun,
          analytics: isDryRun ? null : analytics,
        );

    var example = entrypoint.example;
    if (!isDryRun &&
        asBool(argResults['example'], whenNull: true) &&
        example != null) {
      await example.acquireDependencies(
        SolveType.get,
        precompile: asBool(argResults['precompile']),
        summaryOnly: true,
        analytics: analytics,
      );
    }
  }

  Pubspec _removePackagesFromPubspec(
    Pubspec original,
    Iterable<_PackageRemoval> packages,
  ) {
    final dependencies = {...original.dependencies};
    final devDependencies = {...original.devDependencies};
    final overrides = {...original.dependencyOverrides};

    for (final package in packages) {
      if (package.removeFromOverride) {
        overrides.remove(package.name);
      } else {
        dependencies.remove(package.name);
        devDependencies.remove(package.name);
      }
    }
    return Pubspec(
      original.name,
      version: original.version,
      sdkConstraints: original.sdkConstraints,
      dependencies: dependencies.values,
      devDependencies: devDependencies.values,
      dependencyOverrides: overrides.values,
    );
  }

  /// Writes the changes to the pubspec file
  void _writeRemovalToPubspec(Iterable<_PackageRemoval> packages) {
    ArgumentError.checkNotNull(packages, 'packages');

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));

    for (final package in packages) {
      final dependencyKeys = package.removeFromOverride
          ? ['dependency_overrides']
          : ['dependencies', 'dev_dependencies'];
      var found = false;
      final name = package.name;

      /// There may be packages where the dependency is declared both in
      /// dependencies and dev_dependencies - remove it from both in that case.
      for (final dependencyKey in dependencyKeys) {
        final dependenciesNode = yamlEditor
            .parseAt([dependencyKey], orElse: () => YamlScalar.wrap(null));

        if (dependenciesNode is YamlMap && dependenciesNode.containsKey(name)) {
          yamlEditor.remove([dependencyKey, name]);
          found = true;
          // Check if the dependencies or dev_dependencies map is now empty
          // If it is empty, remove the key as well
          if ((yamlEditor.parseAt([dependencyKey]) as YamlMap).isEmpty) {
            yamlEditor.remove([dependencyKey]);
          }
        }
      }
      if (!found) {
        log.warning(
          'Package "$name" was not found in ${entrypoint.pubspecPath}!',
        );
      }
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}

class _PackageRemoval {
  final String name;
  final bool removeFromOverride;
  _PackageRemoval(this.name, {required this.removeFromOverride});
}
