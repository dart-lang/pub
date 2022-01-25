// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../pubspec.dart';
import '../solver.dart';

/// Handles the `remove` pub command. Removes dependencies from `pubspec.yaml`,
/// and performs an operation similar to `pub get`. Unlike `pub add`, this
/// command supports the removal of multiple dependencies.
class RemoveCommand extends PubCommand {
  @override
  String get name => 'remove';
  @override
  String get description => 'Removes a dependency from the current package.';
  @override
  String get argumentsDescription => '<package>';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-remove';
  @override
  bool get isOffline => argResults['offline'];

  bool get isDryRun => argResults['dry-run'];

  RemoveCommand() {
    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Precompile executables in immediate dependencies.');

    argParser.addFlag(
      'example',
      help: 'Also update dependencies in `example/` (if it exists).',
      hide: true,
    );

    argParser.addOption('directory',
        abbr: 'C', help: 'Run this in the directory<dir>.', valueHelp: 'dir');
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be removed.');
    }

    final packages = Set<String>.from(argResults.rest);

    if (isDryRun) {
      final rootPubspec = entrypoint.root.pubspec;
      final newPubspec = _removePackagesFromPubspec(rootPubspec, packages);
      final newRoot = Package.inMemory(newPubspec);

      await Entrypoint.inMemory(newRoot, cache, lockFile: entrypoint.lockFile)
          .acquireDependencies(SolveType.get,
              precompile: argResults['precompile'],
              dryRun: true,
              analytics: null);
    } else {
      /// Update the pubspec.
      _writeRemovalToPubspec(packages);

      /// Create a new [Entrypoint] since we have to reprocess the updated
      /// pubspec file.
      final updatedEntrypoint = Entrypoint(directory, cache);
      await updatedEntrypoint.acquireDependencies(
        SolveType.get,
        precompile: argResults['precompile'],
        analytics: analytics,
      );

      var example = entrypoint.example;
      if (argResults['example'] && example != null) {
        await example.acquireDependencies(
          SolveType.get,
          precompile: argResults['precompile'],
          onlyReportSuccessOrFailure: true,
          analytics: analytics,
        );
      }
    }
  }

  Pubspec _removePackagesFromPubspec(Pubspec original, Set<String> packages) {
    final originalDependencies = original.dependencies.values;
    final originalDevDependencies = original.devDependencies.values;

    final newDependencies = originalDependencies
        .where((dependency) => !packages.contains(dependency.name));
    final newDevDependencies = originalDevDependencies
        .where((dependency) => !packages.contains(dependency.name));

    return Pubspec(
      original.name,
      version: original.version,
      sdkConstraints: original.sdkConstraints,
      dependencies: newDependencies,
      devDependencies: newDevDependencies,
      dependencyOverrides: original.dependencyOverrides.values,
    );
  }

  /// Writes the changes to the pubspec file
  void _writeRemovalToPubspec(Set<String> packages) {
    ArgumentError.checkNotNull(packages, 'packages');

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));

    for (var package in packages) {
      var found = false;

      /// There may be packages where the dependency is declared both in
      /// dependencies and dev_dependencies.
      for (final dependencyKey in ['dependencies', 'dev_dependencies']) {
        final dependenciesNode = yamlEditor
            .parseAt([dependencyKey], orElse: () => YamlScalar.wrap(null));

        if (dependenciesNode is YamlMap &&
            dependenciesNode.containsKey(package)) {
          if (dependenciesNode.length == 1) {
            yamlEditor.remove([dependencyKey]);
          } else {
            yamlEditor.remove([dependencyKey, package]);
          }

          found = true;
        }
      }

      if (!found) {
        log.warning('Package "$package" was not found in pubspec.yaml!');
      }

      /// Windows line endings are already handled by [yamlEditor]
      writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
    }
  }
}
