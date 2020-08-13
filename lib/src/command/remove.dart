// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
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
  String get invocation => 'pub remove <package>';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-remove';
  @override
  bool get isOffline => argResults['offline'];

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
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be removed.');
    }

    /// Update the pubspec.
    _removePackagesFromPubspec(Set<String>.from(argResults.rest).toList());

    await Entrypoint.current(cache).acquireDependencies(SolveType.GET,
        dryRun: argResults['dry-run'], precompile: argResults['precompile']);
  }

  /// Writes the changes to the pubspec file
  void _removePackagesFromPubspec(List<String> packages) {
    ArgumentError.checkNotNull(packages, 'packages');

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));

    for (var package in packages) {
      var found = false;

      /// There may be packages where the dependency is declared both in
      /// dependencies and dev_dependencies.
      for (final dependencyKey in ['dependencies', 'dev_dependencies']) {
        if (yamlEditor.parseAt([dependencyKey, package], orElse: () => null) !=
            null) {
          yamlEditor.remove([dependencyKey, package]);
          found = true;
        }
      }

      if (!found) {
        log.warning('Package $package was not found in the pubspec! '
            'Please ensure that you spelled the package name correctly!');
      }

      /// Windows line endings are already handled by [yamlEditor]
      writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
    }
  }
}
