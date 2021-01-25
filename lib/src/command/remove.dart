// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../pubspec.dart';
import '../solver.dart';
import '../yaml_edit/editor.dart';

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

      await Entrypoint.global(newRoot, entrypoint.lockFile, cache)
          .acquireDependencies(
        SolveType.GET,
        precompile: argResults['precompile'],
        dryRun: true,
      );
    } else {
      /// Update the pubspec.
      _writeRemovalToPubspec(packages);

      await Entrypoint.current(cache).acquireDependencies(SolveType.GET,
          precompile: argResults['precompile']);
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
        final dependenciesNode =
            yamlEditor.parseAt([dependencyKey], orElse: () => null);

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
