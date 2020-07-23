// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../command.dart';
import '../package_name.dart';
import '../utils.dart';

/// Handles the `global activate` pub command.
class GlobalActivateCommand extends PubCommand {
  @override
  String get name => 'activate';
  @override
  String get description => "Make a package's executables globally available.";
  @override
  String get invocation => 'pub global activate <package> [version-constraint]';

  GlobalActivateCommand() {
    argParser.addOption('source',
        abbr: 's',
        help: 'The source used to find the package.',
        allowed: ['git', 'hosted', 'path'],
        defaultsTo: 'hosted');

    argParser.addMultiOption('features',
        abbr: 'f', help: 'Feature(s) to enable.', hide: true);

    argParser.addMultiOption('omit-features',
        abbr: 'F', help: 'Feature(s) to disable.', hide: true);

    argParser.addFlag('no-executables',
        negatable: false, help: 'Do not put executables on PATH.');

    argParser.addMultiOption('executable',
        abbr: 'x', help: 'Executable(s) to place on PATH.');

    argParser.addFlag('overwrite',
        negatable: false,
        help: 'Overwrite executables from other packages with the same name.');

    argParser.addOption('hosted-url',
        abbr: 'u',
        help:
            'A custom pub server URL for the package. Only applies when using the `hosted` source.');
  }

  @override
  Future run() {
    // Default to `null`, which means all executables.
    List<String> executables;
    if (argResults.wasParsed('executable')) {
      if (argResults.wasParsed('no-executables')) {
        usageException('Cannot pass both --no-executables and --executable.');
      }

      executables = argResults['executable'] as List<String>;
    } else if (argResults['no-executables']) {
      // An empty list means no executables.
      executables = [];
    }

    var features = <String, FeatureDependency>{};
    for (var feature in argResults['features'] ?? []) {
      features[feature] = FeatureDependency.required;
    }
    for (var feature in argResults['omit-features'] ?? []) {
      if (features.containsKey(feature)) {
        usageException('Cannot both enable and disable $feature.');
      }

      features[feature] = FeatureDependency.unused;
    }

    var overwrite = argResults['overwrite'];
    var hostedUrl = argResults['hosted-url'];
    Iterable<String> args = argResults.rest;

    dynamic readArg([String error]) {
      if (args.isEmpty) usageException(error);
      var arg = args.first;
      args = args.skip(1);
      return arg;
    }

    void validateNoExtraArgs() {
      if (args.isEmpty) return;
      var unexpected = args.map((arg) => '"$arg"');
      var arguments = pluralize('argument', unexpected.length);
      usageException('Unexpected $arguments ${toSentence(unexpected)}.');
    }

    switch (argResults['source']) {
      case 'git':
        var repo = readArg('No Git repository given.');
        // TODO(rnystrom): Allow passing in a Git ref too.
        validateNoExtraArgs();
        return globals.activateGit(repo, executables,
            features: features, overwriteBinStubs: overwrite);

      case 'hosted':
        var package = readArg('No package to activate given.');

        // Parse the version constraint, if there is one.
        var constraint = VersionConstraint.any;
        if (args.isNotEmpty) {
          try {
            constraint = VersionConstraint.parse(readArg());
          } on FormatException catch (error) {
            usageException(error.message);
          }
        }

        validateNoExtraArgs();
        return globals.activateHosted(package, constraint, executables,
            features: features, overwriteBinStubs: overwrite, url: hostedUrl);

      case 'path':
        if (features.isNotEmpty) {
          // Globally-activated path packages just use the existing lockfile, so
          // we can't change the feature selection.
          usageException('--features and --omit-features may not be used with '
              'the path source.');
        }

        var path = readArg('No package to activate given.');
        validateNoExtraArgs();
        return globals.activatePath(path, executables,
            overwriteBinStubs: overwrite);
    }

    throw StateError('unreachable');
  }
}
