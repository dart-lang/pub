// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../command.dart';
import '../command_runner.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package_name.dart';
import '../pubspec.dart';
import '../sdk.dart';
import '../solver/type.dart';
import '../source/hosted.dart';
import '../source/root.dart';
import '../utils.dart';

class UnpackCommand extends PubCommand {
  @override
  String get name => 'unpack';

  @override
  String get description => '''
Downloads a package and unpacks it in place.

For example:

  $topLevelProgram pub unpack foo

Downloads and extracts the latest stable package:foo from pub.dev in a
directory `foo-<version>`.

  $topLevelProgram pub unpack foo:1.2.3-pre --no-resolve

Downloads and extracts package:foo version 1.2.3-pre in a directory
`foo-1.2.3-pre` without running running implicit `pub get`.

  $topLevelProgram pub unpack foo --output=archives

Downloads and extracts latest stable version of package:foo in a directory
`archives/foo-<version>`.

  $topLevelProgram pub unpack 'foo:{hosted:"https://my_repo.org"}'

Downloads and extracts latest stable version of package:foo from my_repo.org
in a directory `foo-<version>`.
''';

  @override
  String get argumentsDescription => 'package-name[:constraint]';

  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-unpack';

  @override
  bool get takesArguments => true;

  UnpackCommand() {
    argParser.addFlag(
      'resolve',
      help: 'Whether to do pub get in the downloaded folder',
      defaultsTo: true,
      hide: log.verbosity != log.Verbosity.all,
    );
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'overwrites an existing folder if it exists',
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Download and extract the package in this dir',
      defaultsTo: '.',
    );
  }

  static final _argRegExp = RegExp(
    r'^(?<name>[a-zA-Z0-9_.]+)'
    r'(?::(?<descriptor>.*))?$',
  );

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      usageException('Provide a package name');
    }
    if (argResults.rest.length > 1) {
      usageException('Please provide only a single package name');
    }
    final arg = argResults.rest[0];
    final match = _argRegExp.firstMatch(arg);
    if (match == null) {
      usageException('Use the form package:constraint to specify the package.');
    }
    final parseResult = _parseDescriptor(
      match.namedGroup('name')!,
      match.namedGroup('descriptor'),
    );

    if (parseResult.description is! HostedDescription) {
      fail('Can only fetch hosted packages.');
    }
    final versions = await parseResult.source
        .doGetVersions(parseResult.toRef(), null, cache);
    final constraint = parseResult.constraint;
    versions.removeWhere((id) => !constraint.allows(id.version));
    if (versions.isEmpty) {
      fail('No matching versions of ${parseResult.name}.');
    }
    versions.sort((id1, id2) => id1.version.compareTo(id2.version));

    final id = versions.last;
    final name = id.name;

    final outputArg = argResults.optionWithDefault('output');
    final destinationDir = p.join(outputArg, '$name-${id.version}');
    if (entryExists(destinationDir)) {
      if (argResults.flag('force')) {
        deleteEntry(destinationDir);
      } else {
        fail(
          'Target directory `$destinationDir` already exists. Use --force to overwrite',
        );
      }
    }
    await log.progress(
      'Downloading $name ${id.version} to `$destinationDir`',
      () async {
        await cache.hosted.downloadInto(id, destinationDir, cache);
      },
    );
    final e = Entrypoint(
      destinationDir,
      cache,
    );
    if (argResults.flag('resolve')) {
      try {
        await e.acquireDependencies(SolveType.get);
      } finally {
        log.message('To explore type: cd $destinationDir');
        if (e.example != null) {
          log.message(
            'To explore the example type: cd ${e.example!.workspaceRoot.dir}',
          );
        }
      }
    }
  }

  PackageRange _parseDescriptor(
    String packageName,
    String? descriptor,
  ) {
    late final defaultDescription =
        HostedDescription(packageName, cache.hosted.defaultUrl);
    if (descriptor == null) {
      return PackageRange(
        PackageRef(packageName, defaultDescription),
        VersionConstraint.any,
      );
    }
    try {
      // An unquoted version constraint is not always valid yaml.
      // But we want to allow it here anyways.
      final constraint = VersionConstraint.parse(descriptor);
      return PackageRange(
        PackageRef(packageName, defaultDescription),
        constraint,
      );
    } on FormatException {
      final parsedDescriptor = loadYaml(descriptor);
      // Use the pubspec parsing mechanism for parsing the descriptor.
      final Pubspec dummyPubspec;
      try {
        dummyPubspec = Pubspec.fromMap(
          {
            'dependencies': {packageName: parsedDescriptor},
            'environment': {'sdk': sdk.version.toString()},
          },
          cache.sources,
          // Resolve relative paths relative to current, not where the pubspec.yaml is.
          location: p.toUri(p.join(p.current, 'descriptor')),
          containingDescription: RootDescription('.'),
        );
      } on FormatException catch (e) {
        usageException('Failed parsing package specification: ${e.message}');
      }
      return dummyPubspec.dependencies[packageName]!;
    }
  }
}
