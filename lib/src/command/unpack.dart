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
import '../utils.dart';

/// Handles the `deps` pub command.
class UnpackCommand extends PubCommand {
  @override
  String get name => 'unpack';

  @override
  String get description => '''
Downloads a package and unpacks it in place.

For example:

  $topLevelProgram pub unpack foo

Downloads and extracts the lastest stable package:foo from pub.dev in a
directory `foo-<version>`.

  $topLevelProgram pub unpack foo:1.2.3-pre

Downloads and extracts package:foo version 1.2.3-pre in a directory
`foo-1.2.3-pre`.

  $topLevelProgram pub unpack foo --output=archives

Downloads and extracts latest stable version of package:foo in a directory
`archives/foo-<version>`.

  $topLevelProgram pub unpack 'foo:{hosted:"https://my_repo.org"}'

Downloads and extracts latest stable version of package:foo from my_repo.org
in a directory `foo-<version>`.


Will resolve dependencies in the folder unless `--no-resolve` is passed.
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

    if (parseResult.ref.description is! HostedDescription) {
      fail('Can only fetch hosted packages.');
    }
    final versions = await parseResult.ref.source
        .doGetVersions(parseResult.ref, null, cache);
    final constraint = parseResult.constraint;
    if (constraint != null) {
      versions.removeWhere((id) => !constraint.allows(id.version));
    }
    if (versions.isEmpty) {
      fail('No matching versions of ${parseResult.ref.name}.');
    }
    versions.sort((id1, id2) => id1.version.compareTo(id2.version));

    final id = versions.last;
    final name = id.name;

    final outputArg = argResults['output'] as String;
    final destinationDir = p.join(outputArg, '$name-${id.version}');
    if (entryExists(destinationDir)) {
      fail('Target directory `$destinationDir` already exists.');
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
    if (argResults['resolve'] as bool) {
      try {
        await e.acquireDependencies(SolveType.get);
      } finally {
        log.message('To explore type: cd $destinationDir');
        if (e.example != null) {
          log.message('To explore the example type: cd ${e.example!.rootDir}');
        }
      }
    }
  }

  // TODO(sigurdm): Refactor this to share with `add`.
  _ParseResult _parseDescriptor(
    String packageName,
    String? descriptor,
  ) {
    /// We want to allow for [constraint] to take on a `null` value here to
    /// preserve the fact that the user did not specify a constraint.
    VersionConstraint? constraint;

    /// The package to be added.
    PackageRef? ref;

    if (descriptor != null) {
      try {
        // An unquoted version constraint is not always valid yaml.
        // But we want to allow it here anyways.
        constraint = VersionConstraint.parse(descriptor);
      } on FormatException {
        final parsedDescriptor = loadYaml(descriptor);
        // Use the pubspec parsing mechanism for parsing the descriptor.
        final Pubspec dummyPubspec;
        try {
          dummyPubspec = Pubspec.fromMap(
            {
              'dependencies': {
                packageName: parsedDescriptor,
              },
              'environment': {
                'sdk': sdk.version.toString(),
              },
            },
            cache.sources,
            // Resolve relative paths relative to current, not where the pubspec.yaml is.
            location: p.toUri(p.join(p.current, 'descriptor')),
          );
        } on FormatException catch (e) {
          usageException('Failed parsing package specification: ${e.message}');
        }
        final range = dummyPubspec.dependencies[packageName]!;
        if (parsedDescriptor is String) {
          // Ref will be constructed by the default behavior below.
          ref = null;
        } else {
          ref = range.toRef();
        }
        final hasExplicitConstraint = parsedDescriptor is String ||
            (parsedDescriptor is Map &&
                parsedDescriptor.containsKey('version'));
        // If the descriptor has an explicit constraint, use that. Otherwise we
        // infer it.
        if (hasExplicitConstraint) {
          constraint = range.constraint;
        }
      }
    }
    return _ParseResult(
      ref ??
          PackageRef(
            packageName,
            HostedDescription(
              packageName,
              cache.hosted.defaultUrl,
            ),
          ),
      constraint,
    );
  }
}

class _ParseResult {
  final PackageRef ref;
  final VersionConstraint? constraint;
  _ParseResult(this.ref, this.constraint);
}
