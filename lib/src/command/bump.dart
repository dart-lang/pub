// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../io.dart';
import '../log.dart' as log;

/// Handles the `bump` pub command.
///
/// Updates the version of the current package in `pubspec.yaml`. By default,
/// it bumps the version up to the nearest stable patch number. Users may pass
/// in the `--major|--minor|--patch`, which bumps the version up to the nearest
/// stable major/minor/patch numbers accordingly. Users may also pass in a
/// version number as an argument, and the version number will be bumped to the
/// argument accordingly
///
/// **Examples**
/// 1. `pub bump` 1.2.3 -> 1.2.4
/// 2. `pub bump` 1.2.3-dev -> 1.2.3
/// 3. `pub bump --major` 1.2.3 -> 2.0.0
/// 4. `pub bump --minor` 1.2.3 -> 1.3.0
/// 5. `pub bump 3.0.0` 1.2.3 -> 3.0.0
class BumpCommand extends PubCommand {
  @override
  String get name => 'bump';
  @override
  String get description =>
      'Updates the version of the current package in pubspec.yaml.';
  @override
  String get invocation => 'pub bump [version|--major|--minor|--patch]';

  bool get isMajor => argResults['major'];
  bool get isMinor => argResults['minor'];
  bool get isPatch => argResults['patch'];

  BumpCommand() {
    argParser.addFlag('major',
        negatable: false,
        help: 'Bumps the major version number, while resetting the minor and '
            'patch numbers, as well as build/pre-release information. '
            'e.g. 1.2.3 -> 2.0.0');
    argParser.addFlag('minor',
        negatable: false,
        help:
            'Bumps the minor version number, while resetting the patch number, '
            'as well as build/pre-release information. e.g. 1.2.3 -> 1.3.0');
    argParser.addFlag('patch',
        negatable: false,
        help: 'Bumps the patch number. e.g. 1.2.3 -> 1.2.4. If it is '
            'originally a pre-release version, it simply removes the '
            'pre-release tag instead. e.g. 1.2.3-dev -> 1.2.3');
  }

  @override
  void run() {
    if ((isMajor && isMinor) || (isMajor && isPatch) || (isMinor && isPatch)) {
      usageException('Only one flag should be specified at most');
    }

    if (argResults.rest.isNotEmpty && (isMajor || isMinor || isPatch)) {
      usageException('Must not specify a version to bump to along with flags');
    }

    final initialVersion = entrypoint.root.version;
    Version finalVersion;

    if (argResults.rest.isNotEmpty) {
      if (argResults.rest.length > 1) {
        usageException('Please specify only one version to bump to');
      }

      try {
        finalVersion = Version.parse(argResults.rest.first);
      } on FormatException {
        usageException('Invalid version ${argResults.rest.first} found. '
            'Please ensure that it is correctly formatted according to pub '
            'semver requirements');
      }
    } else {
      final initialMajor = initialVersion.major;
      final initialMinor = initialVersion.minor;
      final initialPatch = initialVersion.patch;

      /// We have already previously ensured that at most one of `isMajor`,
      /// `isMinor`, or `isPatch` is true.
      if (isMajor) {
        finalVersion = Version(initialMajor + 1, 0, 0);
      } else if (isMinor) {
        finalVersion = Version(initialMajor, initialMinor + 1, 0);
      } else {
        /// Both the `--patch` flag and the default options have the same
        /// behavior.

        if (initialVersion.isPreRelease) {
          finalVersion = Version(initialMajor, initialMinor, initialPatch);
        } else {
          finalVersion = Version(initialMajor, initialMinor, initialPatch + 1);
        }
      }
    }
    _updatePubspecVersion(initialVersion, finalVersion);
  }

  /// Writes [finalVersion] to pubspec and report the change.
  void _updatePubspecVersion(Version initialVersion, Version finalVersion) {
    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));

    /// No need to check if the version is not declared in the pubspec
    /// since this update function will add it in if that's the case.
    yamlEditor.update(['version'], finalVersion.toString());

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());

    /// Print the result of the update.
    log.message(
        'Successfully updated version from $initialVersion to $finalVersion');
  }
}
