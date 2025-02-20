// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../io.dart';
import '../log.dart' as log;

class BumpSubcommand extends PubCommand {
  @override
  final String name;
  @override
  final String description;

  final Version Function(Version) updateVersion;
  BumpSubcommand(this.name, this.description, this.updateVersion) {
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: "Report what would change, but don't change anything.",
    );
  }

  String? _versionLines(YamlMap map, String text, String prefix) {
    final entry = map.nodes.entries.firstWhereOrNull(
      (e) => (e.key as YamlNode).value == 'version',
    );
    if (entry == null) return null;

    final firstLine = (entry.key as YamlNode).span.start.line;
    final lastLine = entry.value.span.end.line;
    final lines = text.split('\n');
    return lines
        .sublist(firstLine, lastLine + 1)
        .map((x) => '$prefix$x')
        .join('\n');
  }

  @override
  Future<void> runProtected() async {
    final pubspec = entrypoint.workPackage.pubspec;
    final currentVersion = pubspec.version;

    final newVersion = updateVersion(currentVersion);

    final originalPubspecText = readTextFile(
      entrypoint.workPackage.pubspecPath,
    );
    final yamlEditor = YamlEditor(originalPubspecText);
    yamlEditor.update(['version'], newVersion.toString());
    final updatedPubspecText = yamlEditor.toString();
    final beforeText = _versionLines(pubspec.fields, originalPubspecText, '- ');
    final afterText = _versionLines(
      yamlEditor.parseAt([]) as YamlMap,
      updatedPubspecText,
      '+ ',
    );
    if (argResults.flag('dry-run')) {
      log.message('Would update version from $currentVersion to $newVersion.');
      log.message('Diff:');
      if (beforeText != null) {
        log.message(beforeText);
      }
      if (afterText != null) {
        log.message(afterText);
      }
    } else {
      log.message('Updating version from $currentVersion to $newVersion.');
      log.message('Diff:');

      if (beforeText != null) {
        log.message(beforeText);
      }
      if (afterText != null) {
        log.message(afterText);
        log.message('\nRemember to update `CHANGELOG.md` before publishing.');
      }
      writeTextFile(entrypoint.workPackage.pubspecPath, yamlEditor.toString());
    }
  }
}

class BumpCommand extends PubCommand {
  @override
  String get name => 'bump';
  @override
  String get description => '''
Increases the version number of the current package.
''';

  BumpCommand() {
    addSubcommand(
      BumpSubcommand(
        'major',
        'Increment the major version number (eg. 3.1.2 -> 4.0.0)',
        (v) => v.nextMajor,
      ),
    );
    addSubcommand(
      BumpSubcommand(
        'minor',
        'Increment the minor version number (eg. 3.1.2 -> 3.2.0)',
        (v) => v.nextMinor,
      ),
    );
    addSubcommand(
      BumpSubcommand(
        'patch',
        'Increment the patch version number (eg. 3.1.2 -> 3.1.3)',
        (v) => v.nextPatch,
      ),
    );

    addSubcommand(
      BumpSubcommand(
        'breaking',
        'Increment to the next breaking version (eg. 0.1.2 -> 0.2.0)',
        (v) => v.nextBreaking,
      ),
    );
  }
}
