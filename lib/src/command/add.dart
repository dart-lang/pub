// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../command_runner.dart';
import '../exceptions.dart';
import '../git.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../solver.dart';
import '../source/git.dart';
import '../source/hosted.dart';
import '../source/path.dart';
import '../utils.dart';

/// Handles the `add` pub command. Adds a dependency to `pubspec.yaml` and gets
/// the package. The user may pass in a git constraint, host url, or path as
/// requirements. If no such options are passed in, this command will do a
/// resolution to find the latest version of the package that is compatible with
/// the other dependencies in `pubspec.yaml`, and then enter that as the lower
/// bound in a ^x.y.z constraint.
///
/// The descriptor used to be given with args like --path, --sdk,
/// --git-<option>.
///
/// We still support these arguments, but now the documented way to give the
/// descriptor is to give a yaml-descriptor as in pubspec.yaml.
class AddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description => '''
Add dependencies to `pubspec.yaml`.

Invoking `dart pub add foo bar` will add `foo` and `bar` to `pubspec.yaml`
with a default constraint derived from latest compatible version.

Add to dev_dependencies by prefixing with "dev:".

Make dependency overrides by prefixing with "override:".

Add packages with specific constraints or other sources by giving a descriptor
after a colon.

For example:
  * Add a hosted dependency at newest compatible stable version:
    `$topLevelProgram pub add foo`
  * Add a hosted dev dependency at newest compatible stable version:
    `$topLevelProgram pub add dev:foo`
  * Add a hosted dependency with the given constraint
    `$topLevelProgram pub add foo:^1.2.3`
  * Add multiple dependencies:
    `$topLevelProgram pub add foo dev:bar`
  * Add a path dependency:
    `$topLevelProgram pub add 'foo:{"path":"../foo"}'`
  * Add a hosted dependency:
    `$topLevelProgram pub add 'foo:{"hosted":"my-pub.dev"}'`
  * Add an sdk dependency:
    `$topLevelProgram pub add 'foo:{"sdk":"flutter"}'`
  * Add a git dependency:
    `$topLevelProgram pub add 'foo:{"git":"https://github.com/foo/foo"}'`
  * Add a dependency override:
    `$topLevelProgram pub add 'override:foo:1.0.0'`
  * Add a git dependency with a path and ref specified:
    `$topLevelProgram pub add \\
      'foo:{"git":{"url":"../foo.git","ref":"<branch>","path":"<subdir>"}}'`''';

  @override
  String get argumentsDescription =>
      '[options] [<section>:]<package>[:descriptor] '
      '[<section>:]<package2>[:descriptor] ...]';

  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-add';

  AddCommand() {
    argParser.addFlag(
      'dev',
      abbr: 'd',
      negatable: false,
      help: 'Adds to the development dependencies instead.',
      hide: true,
    );

    // Following options are hidden/deprecated in favor of the new syntax: [dev:]<package>[:descriptor] ...
    // To avoid breaking changes we keep supporting them, but hide them from --help to discourage
    // further use. Combining these with new syntax will fail.
    argParser.addOption(
      'git-url',
      help: 'Git URL of the package',
      hide: true,
    );
    argParser.addOption(
      'git-ref',
      help: 'Git branch or commit to be retrieved',
      hide: true,
    );
    argParser.addOption(
      'git-path',
      help: 'Path of git package in repository',
      hide: true,
    );
    argParser.addOption(
      'hosted-url',
      help: 'URL of package host server',
      hide: true,
    );
    argParser.addOption(
      'path',
      help: 'Add package from local path',
      hide: true,
    );
    argParser.addOption(
      'sdk',
      help: 'add package from SDK source',
      allowed: ['flutter'],
      valueHelp: '[flutter]',
      hide: true,
    );

    argParser.addFlag(
      'offline',
      help: 'Use cached packages instead of accessing the network.',
    );

    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: "Report what dependencies would change but don't change any.",
    );

    argParser.addFlag(
      'precompile',
      help: 'Build executables in immediate dependencies.',
    );
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
    argParser.addFlag(
      'example',
      defaultsTo: true,
      help:
          'Also update dependencies in `example/` after modifying pubspec.yaml in the root package (if it exists).',
      hide: true,
    );
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.length > 1) {
      if (argResults.gitUrl != null) {
        usageException('''
--git-url cannot be used with multiple packages.
Specify multiple git packages with descriptors.''');
      } else if (argResults.path != null) {
        usageException('''
--path cannot be used with multiple packages.
Specify multiple path packages with descriptors.''');
      } else if (argResults.sdk != null) {
        usageException('''
--sdk cannot be used with multiple packages.
Specify multiple sdk packages with descriptors.''');
      }
    }
    if (argResults.rest.isEmpty) {
      usageException('Must specify at least one package to be added.');
    }

    final updates =
        argResults.rest.map((p) => _parsePackage(p, argResults)).toList();

    /// Compute a pubspec that will depend on all the given packages, but the
    /// actual constraint will only be determined after a resolution decides the
    /// best version.
    var resolutionPubspec = entrypoint.root.pubspec;
    for (final update in updates) {
      /// Perform version resolution in-memory.
      resolutionPubspec = await _addPackageToPubspec(resolutionPubspec, update);
    }

    late SolveResult solveResult;

    try {
      /// Use [SolveType.UPGRADE] to solve for the highest version of [package]
      /// in case [package] was already a transitive dependency. In the case
      /// where the user specifies a version constraint, this serves to ensure
      /// that a resolution exists before we update pubspec.yaml.
      // TODO(sigurdm): We should really use a spinner here.
      solveResult = await resolveVersions(
        SolveType.upgrade,
        cache,
        Package.inMemory(resolutionPubspec),
      );
    } on GitException {
      final name = updates.first.ref.name;
      dataError('Unable to resolve package "$name" with the given '
          'git parameters.');
    } on SolveFailure catch (e) {
      dataError(e.message);
    } on WrappedException catch (e) {
      /// [WrappedException]s may appear if an invalid [hostUrl] is passed in.
      dataError(e.message);
    }

    /// Verify the results for each package.
    for (final update in updates) {
      final ref = update.ref;
      final name = ref.name;
      final resultPackage = solveResult.packages
          .firstWhere((packageId) => packageId.name == name);

      /// Assert that [resultPackage] is within the original user's expectations.
      final constraint = update.constraint;
      if (constraint != null && !constraint.allows(resultPackage.version)) {
        final dependencyOverrides = resolutionPubspec.dependencyOverrides;
        if (dependencyOverrides.isNotEmpty) {
          dataError('"$name" resolved to "${resultPackage.version}" which '
              'does not satisfy constraint "$constraint". This could be '
              'caused by "dependency_overrides".');
        }
      }
    }
    final newPubspecText = _updatePubspec(solveResult.packages, updates);
    if (!argResults.isDryRun) {
      /// Update the `pubspec.yaml` before calling [acquireDependencies] to
      /// ensure that the modification timestamp on `pubspec.lock` and
      /// `.dart_tool/package_config.json` is newer than `pubspec.yaml`,
      /// ensuring that [entrypoint.assertUptoDate] will pass.
      writeTextFile(entrypoint.pubspecPath, newPubspecText);
    }

    /// Even if it is a dry run, run `acquireDependencies` so that the user
    /// gets a report on the other packages that might change version due
    /// to this new dependency.
    await entrypoint
        .withPubspec(
          Pubspec.parse(
            newPubspecText,
            cache.sources,
            location: Uri.parse(entrypoint.pubspecPath),
          ),
        )
        .acquireDependencies(
          SolveType.get,
          dryRun: argResults.isDryRun,
          precompile: !argResults.isDryRun && argResults.shouldPrecompile,
          analytics: argResults.isDryRun ? null : analytics,
        );

    if (!argResults.isDryRun &&
        argResults.example &&
        entrypoint.example != null) {
      await entrypoint.example!.acquireDependencies(
        SolveType.get,
        precompile: argResults.shouldPrecompile,
        summaryOnly: true,
        analytics: analytics,
      );
    }

    if (isOffline) {
      log.warning('Warning: Packages added when offline may not resolve to '
          'the latest compatible version available.');
    }
  }

  /// Creates a new in-memory [Pubspec] by adding [package] to the
  /// dependencies of [original].
  Future<Pubspec> _addPackageToPubspec(
    Pubspec original,
    _ParseResult package,
  ) async {
    final name = package.ref.name;
    final dependencies = [...original.dependencies.values];
    var devDependencies = [...original.devDependencies.values];
    var dependencyOverrides = [...original.dependencyOverrides.values];

    final dependencyNames = dependencies.map((dependency) => dependency.name);
    final devDependencyNames =
        devDependencies.map((devDependency) => devDependency.name);
    final range =
        package.ref.withConstraint(package.constraint ?? VersionConstraint.any);

    if (package.isOverride) {
      dependencyOverrides.add(range);
    } else if (package.isDev) {
      if (devDependencyNames.contains(name)) {
        log.message('"$name" is already in "dev_dependencies". '
            'Will try to update the constraint.');
        devDependencies.removeWhere((element) => element.name == name);
      }

      /// If package is originally in dependencies and we wish to add it to
      /// dev_dependencies, this is a redundant change, and we should not
      /// remove the package from dependencies, since it might cause the user's
      /// code to break.
      if (dependencyNames.contains(name)) {
        dataError('"$name" is already in "dependencies". '
            'Use "pub remove $name" to remove it before adding it '
            'to "dev_dependencies"');
      }

      devDependencies.add(range);
    } else {
      if (dependencyNames.contains(name)) {
        log.message(
          '"$name" is already in "dependencies". Will try to update the constraint.',
        );
        dependencies.removeWhere((element) => element.name == name);
      }

      /// If package is originally in dev_dependencies and we wish to add it to
      /// dependencies, we remove the package from dev_dependencies, since it is
      /// now redundant.
      if (devDependencyNames.contains(name)) {
        log.message('"$name" was found in dev_dependencies. '
            'Removing "$name" and adding it to dependencies instead.');
        devDependencies.removeWhere((element) => element.name == name);
      }

      dependencies.add(range);
    }

    return Pubspec(
      original.name,
      version: original.version,
      sdkConstraints: original.sdkConstraints,
      dependencies: dependencies,
      devDependencies: devDependencies,
      dependencyOverrides: dependencyOverrides,
    );
  }

  static final _argRegExp = RegExp(
    r'^(?:(?<prefix>dev|override):)?'
    r'(?<name>[a-zA-Z0-9_.]+)'
    r'(?::(?<descriptor>.*))?$',
  );

  static final _lenientArgRegExp = RegExp(
    r'^(?:(?<prefix>[^:]*):)?'
    r'(?<name>[^:]*)'
    r'(?::(?<descriptor>.*))?$',
  );

  /// Split [arg] on ':' and interpret it with the flags in [argResult] either as
  /// an old-style or a new-style descriptor to produce a PackageRef].
  _ParseResult _parsePackage(String arg, ArgResults argResults) {
    var isDev = argResults['dev'] as bool;
    var isOverride = false;

    final match = _argRegExp.firstMatch(arg);
    if (match == null) {
      final match2 = _lenientArgRegExp.firstMatch(arg);
      if (match2 == null) {
        usageException('Could not parse $arg');
      } else {
        if (match2.namedGroup('prefix') != null &&
            match2.namedGroup('descriptor') != null) {
          usageException(
            'The only allowed prefixes are "dev:" and "override:"',
          );
        } else {
          final packageName = match2.namedGroup('descriptor') == null
              ? match2.namedGroup('prefix')
              : match2.namedGroup('name');
          usageException('Not a valid package name: "$packageName"');
        }
      }
    } else if (match.namedGroup('prefix') == 'dev') {
      if (argResults.isDev) {
        usageException("Cannot combine 'dev:' with --dev");
      }
      isDev = true;
    } else if (match.namedGroup('prefix') == 'override') {
      if (argResults.isDev) {
        usageException("Cannot combine 'override:' with --dev");
      }
      isOverride = true;
    }
    final packageName = match.namedGroup('name')!;
    if (!packageNameRegExp.hasMatch(packageName)) {
      usageException('Not a valid package name: "$packageName"');
    }
    final descriptor = match.namedGroup('descriptor');

    if (isOverride && descriptor == null) {
      usageException('A dependency override needs an explicit descriptor.');
    }
    final _PartialParseResult partial;
    if (argResults.hasOldStyleOptions) {
      partial = _parseDescriptorOldStyleArgs(
        packageName,
        descriptor,
        argResults,
      );
    } else {
      partial = _parseDescriptorNewStyle(packageName, descriptor);
    }

    return _ParseResult(
      partial.ref,
      partial.constraint,
      isDev: isDev,
      isOverride: isOverride,
    );
  }

  /// Parse [descriptor] to return the corresponding [_ParseResult] using the
  /// arguments given in [argResults] to configure the description.
  ///
  /// [descriptor] should be a constraint as parsed by
  /// [VersionConstraint.parse]. If it fails to parse as a version constraint
  /// but could parse with [_parseDescriptorNewStyle()] a specific usage
  /// description is issued.
  ///
  /// Examples:
  /// ```
  /// retry
  /// retry:2.0.0
  /// retry:^2.0.0
  /// retry:'>=2.0.0'
  /// retry:'>2.0.0 <3.0.1'
  /// 'retry:>2.0.0 <3.0.1'
  /// retry:any
  /// ```
  ///
  /// If a version constraint is provided when the `--path` or any of the
  /// `--git-<option>` options are used, a [UsageException] will be thrown.
  ///
  /// Packages must either be a git, hosted, sdk, or path package. Mixing of
  /// options is not allowed and will cause a [UsageException] to be thrown.
  ///
  /// If any of the other git options are defined when `--git-url` is not
  /// defined, an error will be thrown.
  ///
  /// The returned [_PartialParseResult] will always have `ref!=null`.
  _PartialParseResult _parseDescriptorOldStyleArgs(
    String packageName,
    String? descriptor,
    ArgResults argResults,
  ) {
    final conflictingFlagSets = [
      ['git-url', 'git-ref', 'git-path'],
      ['hosted-url'],
      ['path'],
      ['sdk'],
    ];

    for (final flag
        in conflictingFlagSets.expand((s) => s).where(argResults.wasParsed)) {
      final conflictingFlag = conflictingFlagSets
          .where((s) => !s.contains(flag))
          .expand((s) => s)
          .firstWhereOrNull(argResults.wasParsed);
      if (conflictingFlag != null) {
        usageException(
            'Packages can only have one source, "pub add" flags "--$flag" and '
            '"--$conflictingFlag" are conflicting.');
      }
    }

    /// We want to allow for [constraint] to take on a `null` value here to
    /// preserve the fact that the user did not specify a constraint.
    VersionConstraint? constraint;
    try {
      constraint =
          descriptor == null ? null : VersionConstraint.parse(descriptor);
    } on FormatException catch (e) {
      var couldParseAsNewStyle = true;
      try {
        _parseDescriptorNewStyle(packageName, descriptor);
        // If parsing the descriptor as a new-style descriptor succeeds we
        // can give this more specific error message.
      } catch (_) {
        couldParseAsNewStyle = false;
      }
      if (couldParseAsNewStyle) {
        usageException(
          '--dev, --path, --sdk, --git-url, --git-path and --git-ref cannot be combined with a descriptor.',
        );
      } else {
        usageException('Invalid version constraint: ${e.message}');
      }
    }

    /// The package to be added.
    late final PackageRef ref;
    final path = argResults.path;
    if (argResults.hasGitOptions) {
      final gitUrl = argResults.gitUrl;
      if (gitUrl == null) {
        usageException('The `--git-url` is required for git dependencies.');
      }
      Uri parsed;
      try {
        parsed = Uri.parse(gitUrl);
      } on FormatException catch (e) {
        usageException('The --git-url must be a valid url: ${e.message}.');
      }

      /// Process the git options to return the simplest representation to be
      /// added to the pubspec.

      ref = PackageRef(
        packageName,
        GitDescription(
          url: parsed.toString(),
          containingDir: p.current,
          ref: argResults.gitRef,
          path: argResults.gitPath,
        ),
      );
    } else if (path != null) {
      ref = PackageRef(
        packageName,
        PathDescription(p.absolute(path), p.isRelative(path)),
      );
    } else if (argResults.sdk != null) {
      ref = cache.sdk.parseRef(packageName, argResults.sdk);
    } else {
      ref = PackageRef(
        packageName,
        HostedDescription(
          packageName,
          argResults.hostedUrl ?? cache.hosted.defaultUrl,
        ),
      );
    }
    return _PartialParseResult(ref, constraint);
  }

  /// Parse [package] to return the corresponding [_ParseResult].
  ///
  /// [package] must be written in the format
  /// `<package-name>[:descriptor>]`, where quotations should be used if
  /// necessary.
  ///
  /// `descriptor` is what you would put in a pubspec.yaml in the dependencies
  /// section.
  ///
  /// Assumes that none of '--git-url', '--git-ref', '--git-path', '--path' and
  /// '--sdk' are present in [argResults].
  ///
  ///
  /// Examples:
  /// ```
  /// retry
  /// retry:2.0.0
  /// dev:retry:^2.0.0
  /// retry:'>=2.0.0'
  /// retry:'>2.0.0 <3.0.1'
  /// 'retry:>2.0.0 <3.0.1'
  /// retry:any
  /// 'retry:{"path":"../foo"}'
  /// 'retry:{"git":{"url":"../foo","ref":"branchname"},"version":"^1.2.3"}'
  /// 'retry:{"sdk":"flutter"}'
  /// 'retry:{"hosted":"mypub.dev"}'
  /// ```
  ///
  /// The --path --sdk and --git-<option> arguments cannot be combined with a
  /// non-string descriptor.
  ///
  /// If a version constraint is provided when the `--path` or any of the
  /// `--git-<option>` options are used, a [PackageParseError] will be thrown.
  ///
  /// Packages must either be a git, hosted, sdk, or path package. Mixing of
  /// options is not allowed and will cause a [PackageParseError] to be thrown.
  ///
  /// If any of the other git options are defined when `--git-url` is not
  /// defined, an error will be thrown.
  ///
  /// Returns a `ref` of `null` if the descriptor did not specify a source.
  /// Then the source will be determined by the old-style arguments.
  _PartialParseResult _parseDescriptorNewStyle(
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
              }
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
    return _PartialParseResult(
      ref ??
          PackageRef(
            packageName,
            HostedDescription(
              packageName,
              argResults.hostedUrl ?? cache.hosted.defaultUrl,
            ),
          ),
      constraint,
    );
  }

  /// Calculates the updates to the pubspec file.
  String _updatePubspec(
    List<PackageId> resultPackages,
    List<_ParseResult> updates,
  ) {
    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));
    log.io('Reading ${entrypoint.pubspecPath}.');
    log.fine('Contents:\n$yamlEditor');

    for (final update in updates) {
      final dependencyKey = update.isDev
          ? 'dev_dependencies'
          : (update.isOverride ? 'dependency_overrides' : 'dependencies');
      final constraint = update.constraint;
      final ref = update.ref;
      final name = ref.name;
      final resultId = resultPackages.firstWhere((id) => id.name == name);
      var description = ref.description;
      final versionConstraintString =
          constraint == null ? '^${resultId.version}' : constraint.toString();
      late Object? pubspecInformation;
      if (description is HostedDescription &&
          description.url == cache.hosted.defaultUrl) {
        pubspecInformation = versionConstraintString;
      } else {
        pubspecInformation = {
          ref.source.name: ref.description.serializeForPubspec(
            containingDir: entrypoint.rootDir,
            languageVersion: entrypoint.root.pubspec.languageVersion,
          ),
          if (description is HostedDescription || constraint != null)
            'version': versionConstraintString
        };
      }

      if (yamlEditor.parseAt(
            [dependencyKey],
            orElse: () => YamlScalar.wrap(null),
          ).value ==
          null) {
        // Handle the case where [dependencyKey] does not already exist.
        // We ensure it is in Block-style by default.
        yamlEditor.update(
          [dependencyKey],
          wrapAsYamlNode(
            {name: pubspecInformation},
            collectionStyle: CollectionStyle.BLOCK,
          ),
        );
      } else {
        final packagePath = [dependencyKey, name];

        yamlEditor.update(packagePath, pubspecInformation);
      }

      /// Remove the package from dev_dependencies if we are adding it to
      /// dependencies. Refer to [_addPackageToPubspec] for additional discussion.
      if (!update.isDev && !update.isOverride) {
        final devDependenciesNode = yamlEditor
            .parseAt(['dev_dependencies'], orElse: () => YamlScalar.wrap(null));

        if (devDependenciesNode is YamlMap &&
            devDependenciesNode.containsKey(name)) {
          if (devDependenciesNode.length == 1) {
            yamlEditor.remove(['dev_dependencies']);
          } else {
            yamlEditor.remove(['dev_dependencies', name]);
          }

          log.fine('Removed $name from "dev_dependencies".');
        }
      }
    }

    return yamlEditor.toString();
  }
}

class _PartialParseResult {
  final PackageRef ref;
  final VersionConstraint? constraint;
  _PartialParseResult(this.ref, this.constraint);
}

class _ParseResult {
  final PackageRef ref;
  final VersionConstraint? constraint;
  final bool isDev;
  final bool isOverride;
  _ParseResult(
    this.ref,
    this.constraint, {
    required this.isDev,
    required this.isOverride,
  });
}

extension on ArgResults {
  bool get isDev => this['dev'];
  bool get isDryRun => this['dry-run'];
  String? get gitUrl => this['git-url'];
  String? get gitPath => this['git-path'];
  String? get gitRef => this['git-ref'];
  String? get hostedUrl => this['hosted-url'];
  String? get path => this['path'];
  String? get sdk => this['sdk'];
  bool get hasOldStyleOptions =>
      hasGitOptions ||
      path != null ||
      sdk != null ||
      hostedUrl != null ||
      isDev;
  bool get shouldPrecompile => this['precompile'];
  bool get example => this['example'];
  bool get hasGitOptions => gitUrl != null || gitRef != null || gitPath != null;
}
