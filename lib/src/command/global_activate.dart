// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';

import '../command.dart';
import '../source/hosted.dart';
import '../utils.dart';

/// Handles the `global activate` pub command.
class GlobalActivateCommand extends PubCommand {
  @override
  String get name => 'activate';
  @override
  String get description => "Make a package's executables globally available.";
  @override
  String get argumentsDescription => '<package> [version-constraint]';

  GlobalActivateCommand() {
    argParser.addOption('source',
        abbr: 's',
        help: 'The source used to find the package.',
        allowed: ['git', 'hosted', 'path'],
        defaultsTo: 'hosted');

    argParser.addOption('git-path', help: 'Path of git package in repository');

    argParser.addOption('git-ref',
        help: 'Git branch or commit to be retrieved');

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
  Future<void> runProtected() async {
    // Default to `null`, which means all executables.
    List<String>? executables;
    if (argResults.wasParsed('executable')) {
      if (argResults.wasParsed('no-executables')) {
        usageException('Cannot pass both --no-executables and --executable.');
      }

      executables = argResults['executable'];
    } else if (argResults['no-executables']) {
      // An empty list means no executables.
      executables = [];
    }

    final overwrite = argResults['overwrite'] as bool;
    Uri? hostedUrl;
    if (argResults.wasParsed('hosted-url')) {
      try {
        hostedUrl = validateAndNormalizeHostedUrl(argResults['hosted-url']);
      } on FormatException catch (e) {
        usageException('Invalid hosted-url: $e');
      }
    }

    Iterable<String> args = argResults.rest;

    String readArg([String error = '']) {
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

    if (argResults['source'] != 'git' &&
        (argResults['git-path'] != null || argResults['git-ref'] != null)) {
      usageException(
          'Options `--git-path` and `--git-ref` can only be used with --source=git.');
    }

    switch (argResults['source']) {
      case 'git':
        var repo = readArg('No Git repository given.');
        validateNoExtraArgs();
        return globals.activateGit(
          repo,
          executables,
          overwriteBinStubs: overwrite,
          path: argResults['git-path'],
          ref: argResults['git-ref'],
        );

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
        return globals.activateHosted(
          package,
          constraint,
          executables,
          overwriteBinStubs: overwrite,
          url: hostedUrl?.toString(),
        );

      case 'path':
        var path = readArg('No package to activate given.');
        validateNoExtraArgs();
        return globals.activatePath(
          path,
          executables,
          overwriteBinStubs: overwrite,
          analytics: analytics,
        );
    }

    throw StateError('unreachable');
  }
}
