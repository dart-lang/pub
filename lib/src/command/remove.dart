// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../exceptions.dart';
import '../io.dart';

/// Handles the `remove` pub command.
class RemoveCommand extends PubCommand {
  @override
  String get name => 'remove';
  @override
  String get description => 'Removes a dependency from the current package.';
  @override
  String get invocation => 'pub remove <package>';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-remove';

  RemoveCommand();

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be removed.');
    }

    /// Update the pubspec.
    _removePackagesFromPubspec(argResults.rest);

    /// Run pub get once we have successfully updated the pubspec
    await runner.run(['get']);
  }

  /// Writes the changes to the pubspec file
  void _removePackagesFromPubspec(List<String> packages) {
    ArgumentError.checkNotNull(packages, 'packages');

    if (entrypoint.pubspecPath == null) {
      throw FileException(
          // Make the package dir absolute because for the entrypoint it'll just
          // be ".", which may be confusing.
          'Could not find a file named "pubspec.yaml" in '
          '"${canonicalize('.')}".',
          entrypoint.pubspecPath);
    }

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));

    for (var package in packages) {
      if (yamlEditor.parseAt(['dependencies', package], orElse: () => null) !=
          null) {
        yamlEditor.remove(['dependencies', package]);
      }

      if (yamlEditor
              .parseAt(['dev_dependencies', package], orElse: () => null) !=
          null) {
        yamlEditor.remove(['dev_dependencies', package]);
      }

      /// Windows line endings are already handled by [yamlEditor]
      writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
    }
  }
}
