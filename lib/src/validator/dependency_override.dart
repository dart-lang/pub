// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../validator.dart';

/// Complains (with a hint) if any of the transitive dependencies of a package's
/// non-dev dependencies are overridden anywhere in the workspace.
class DependencyOverrideValidator extends Validator {
  @override
  Future<void> validate() async {
    final graph = await context.entrypoint.packageGraph;
    final transitiveNonDevDependencies = <String>{};
    final toVisit = [package.name];
    while (toVisit.isNotEmpty) {
      final next = toVisit.removeLast();
      if (transitiveNonDevDependencies.add(next)) {
        toVisit.addAll(graph.packages[next]!.dependencies.keys);
      }
    }

    for (final workspacePackage
        in context.entrypoint.workspaceRoot.transitiveWorkspace) {
      for (final override
          in workspacePackage.pubspec.dependencyOverrides.keys) {
        if (transitiveNonDevDependencies.contains(override)) {
          final overridesFile =
              workspacePackage.pubspec.dependencyOverridesFromOverridesFile
                  ? workspacePackage.pubspecOverridesPath
                  : workspacePackage.pubspecPath;
          hints.add('''
Non-dev dependencies are overridden in $overridesFile.

This indicates you are not testing your package against the same versions of its
dependencies that users will have when they use it.

This might be necessary for packages with cyclic dependencies.

Please be extra careful when publishing.''');
        }
      }
    }
  }
}
