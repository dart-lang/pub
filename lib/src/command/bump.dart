// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../io.dart';
import '../log.dart' as log;

class BumpCommand extends PubCommand {
  @override
  String get name => 'bump';
  @override
  String get description => '''
Increases the version number of the current package.
''';

  BumpCommand() {
    argParser.addFlag(
      'major',
      negatable: false,
      help: 'Increment the major version number (eg. 3.1.2 -> 4.0.0)',
    );
    argParser.addFlag(
      'minor',
      negatable: false,
      help: 'Increment the minor version number (eg. 3.1.2 -> 3.2.0)',
    );
    argParser.addFlag(
      'patch',
      negatable: false,
      help: 'Increment the patch version number (eg. 3.1.2 -> 3.1.3)',
    );
    argParser.addFlag(
      'breaking',
      negatable: false,
      help: 'Increment to the next breaking version (eg. 0.1.2 -> 0.2.0)',
    );
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: "Report what would change but don't change anything.",
    );
  }

  @override
  Future<void> runProtected() async {
    final currentVersion = entrypoint.workPackage.pubspec.version;
    final Version newVersion;

    final breaking = argResults.flag('breaking');
    final major = argResults.flag('major');
    final minor = argResults.flag('minor');
    final patch = argResults.flag('patch');
    final optionCount =
        [breaking, major, minor, patch].fold(0, (p, v) => p + (v ? 1 : 0));
    if (optionCount != 1) {
      usageException('Provide exactly one of the options '
          '`--breaking`, `--major`, `--minor` or `--patch`.');
    }

    if (breaking) {
      newVersion = currentVersion.nextBreaking;
    } else if (major) {
      newVersion = currentVersion.nextMajor;
    } else if (minor) {
      newVersion = currentVersion.nextMinor;
    } else if (patch) {
      newVersion = currentVersion.nextPatch;
    } else {
      throw StateError('Should not be possible');
    }

    if (argResults.flag('dry-run')) {
      log.message('Would update version from $currentVersion to $newVersion.');
    } else {
      log.message('Updating version from $currentVersion to $newVersion.');
      final yamlEditor =
          YamlEditor(readTextFile(entrypoint.workPackage.pubspecPath));

      yamlEditor.update(['version'], newVersion.toString());
      writeTextFile(entrypoint.workPackage.pubspecPath, yamlEditor.toString());
    }
  }
}
