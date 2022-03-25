// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart' show IterableExtension;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../exceptions.dart';
import '../git.dart';
import '../io.dart';
import '../language_version.dart';
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
/// Currently supports only adding one dependency at a time.
class AddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description => 'Add dependencies to pubspec.yaml.';
  @override
  String get argumentsDescription =>
      '<package>[:<constraint>] [<package2>[:<constraint2>]...] [options]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-add';
  @override
  bool get isOffline => argResults['offline'];

  bool get isDev => argResults['dev'];
  bool get isDryRun => argResults['dry-run'];
  String? get gitUrl => argResults['git-url'];
  String? get gitPath => argResults['git-path'];
  String? get gitRef => argResults['git-ref'];
  String? get hostUrl => argResults['hosted-url'];
  String? get path => argResults['path'];
  String? get sdk => argResults['sdk'];

  bool get hasGitOptions => gitUrl != null || gitRef != null || gitPath != null;
  bool get hasHostOptions => hostUrl != null;

  bool get isHosted => !hasGitOptions && path == null && path == null;

  AddCommand() {
    argParser.addFlag('dev',
        abbr: 'd',
        negatable: false,
        help: 'Adds to the development dependencies instead.');

    argParser.addOption('git-url', help: 'Git URL of the package');
    argParser.addOption('git-ref',
        help: 'Git branch or commit to be retrieved');
    argParser.addOption('git-path', help: 'Path of git package in repository');
    argParser.addOption('hosted-url', help: 'URL of package host server');
    argParser.addOption('path', help: 'Add package from local path');
    argParser.addOption('sdk',
        help: 'add package from SDK source',
        allowed: ['flutter'],
        valueHelp: '[flutter]');
    argParser.addFlag(
      'example',
      help:
          'Also update dependencies in `example/` after modifying pubspec.yaml in the root package (if it exists).',
      hide: true,
    );

    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Build executables in immediate dependencies.');
    argParser.addOption('directory',
        abbr: 'C', help: 'Run this in the directory <dir>.', valueHelp: 'dir');
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify at least one package to be added.');
    } else if (argResults.rest.length > 1 && gitUrl != null) {
      usageException('Can only add a single git package at a time.');
    } else if (argResults.rest.length > 1 && path != null) {
      usageException('Can only add a single local package at a time.');
    }
    final languageVersion = entrypoint.root.pubspec.languageVersion;
    final updates =
        argResults.rest.map((p) => _parsePackage(p, languageVersion)).toList();

    var updatedPubSpec = entrypoint.root.pubspec;
    for (final update in updates) {
      /// Perform version resolution in-memory.
      updatedPubSpec = await _addPackageToPubspec(updatedPubSpec, update);
    }

    late SolveResult solveResult;

    try {
      /// Use [SolveType.UPGRADE] to solve for the highest version of [package]
      /// in case [package] was already a transitive dependency. In the case
      /// where the user specifies a version constraint, this serves to ensure
      /// that a resolution exists before we update pubspec.yaml.
      // TODO(sigurdm): We should really use a spinner here.
      solveResult = await resolveVersions(
          SolveType.upgrade, cache, Package.inMemory(updatedPubSpec));
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
        final dependencyOverrides = updatedPubSpec.dependencyOverrides;
        if (dependencyOverrides.isNotEmpty) {
          dataError('"$name" resolved to "${resultPackage.version}" which '
              'does not satisfy constraint "$constraint". This could be '
              'caused by "dependency_overrides".');
        }
      }
    }
    if (isDryRun) {
      /// Even if it is a dry run, run `acquireDependencies` so that the user
      /// gets a report on the other packages that might change version due
      /// to this new dependency.
      final newRoot = Package.inMemory(updatedPubSpec);

      await Entrypoint.inMemory(newRoot, cache,
              solveResult: solveResult, lockFile: entrypoint.lockFile)
          .acquireDependencies(SolveType.get,
              dryRun: true,
              precompile: argResults['precompile'],
              analytics: analytics);
    } else {
      /// Update the `pubspec.yaml` before calling [acquireDependencies] to
      /// ensure that the modification timestamp on `pubspec.lock` and
      /// `.dart_tool/package_config.json` is newer than `pubspec.yaml`,
      /// ensuring that [entrypoint.assertUptoDate] will pass.
      _updatePubspec(solveResult.packages, updates, isDev);

      /// Create a new [Entrypoint] since we have to reprocess the updated
      /// pubspec file.
      final updatedEntrypoint = Entrypoint(directory, cache);
      await updatedEntrypoint.acquireDependencies(
        SolveType.get,
        precompile: argResults['precompile'],
        analytics: analytics,
      );

      if (argResults['example'] && entrypoint.example != null) {
        await entrypoint.example!.acquireDependencies(
          SolveType.get,
          precompile: argResults['precompile'],
          onlyReportSuccessOrFailure: true,
          analytics: analytics,
        );
      }
    }

    if (isOffline) {
      log.warning('Warning: Packages added when offline may not resolve to '
          'the latest compatible version available.');
    }
  }

  /// Creates a new in-memory [Pubspec] by adding [package] to the
  /// dependencies of [original].
  Future<Pubspec> _addPackageToPubspec(
      Pubspec original, _ParseResult package) async {
    final name = package.ref.name;
    final dependencies = [...original.dependencies.values];
    var devDependencies = [...original.devDependencies.values];
    final dependencyNames = dependencies.map((dependency) => dependency.name);
    final devDependencyNames =
        devDependencies.map((devDependency) => devDependency.name);
    final range =
        package.ref.withConstraint(package.constraint ?? VersionConstraint.any);
    if (isDev) {
      /// TODO(walnut): Change the error message once pub upgrade --bump is
      /// released
      if (devDependencyNames.contains(name)) {
        dataError('"$name" is already in "dev_dependencies". '
            'Use "pub upgrade $name" to upgrade to a later version!');
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
      /// TODO(walnut): Change the error message once pub upgrade --bump is
      /// released
      if (dependencyNames.contains(name)) {
        dataError('"$name" is already in "dependencies". '
            'Use "pub upgrade $name" to upgrade to a later version!');
      }

      /// If package is originally in dev_dependencies and we wish to add it to
      /// dependencies, we remove the package from dev_dependencies, since it is
      /// now redundant.
      if (devDependencyNames.contains(name)) {
        log.message('"$name" was found in dev_dependencies. '
            'Removing "$name" and adding it to dependencies instead.');
        devDependencies = devDependencies.where((d) => d.name != name).toList();
      }

      dependencies.add(range);
    }

    return Pubspec(
      original.name,
      version: original.version,
      sdkConstraints: original.sdkConstraints,
      dependencies: dependencies,
      devDependencies: devDependencies,
      dependencyOverrides: original.dependencyOverrides.values,
    );
  }

  /// Parse [package] to return the corresponding [PackageRange], as well as its
  /// representation in `pubspec.yaml`.
  ///
  /// [package] must be written in the format
  /// `<package-name>[:<version-constraint>]`, where quotations should be used
  /// if necessary.
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
  /// `--git-<option>` options are used, a [PackageParseError] will be thrown.
  ///
  /// Packages must either be a git, hosted, sdk, or path package. Mixing of
  /// options is not allowed and will cause a [PackageParseError] to be thrown.
  ///
  /// If any of the other git options are defined when `--git-url` is not
  /// defined, an error will be thrown.
  _ParseResult _parsePackage(String package, LanguageVersion languageVersion) {
    final _conflictingFlagSets = [
      ['git-url', 'git-ref', 'git-path'],
      ['hosted-url'],
      ['path'],
      ['sdk'],
    ];

    for (final flag
        in _conflictingFlagSets.expand((s) => s).where(argResults.wasParsed)) {
      final conflictingFlag = _conflictingFlagSets
          .where((s) => !s.contains(flag))
          .expand((s) => s)
          .firstWhereOrNull(argResults.wasParsed);
      if (conflictingFlag != null) {
        usageException(
            'Packages can only have one source, "pub add" flags "--$flag" and '
            '"--$conflictingFlag" are conflicting.');
      }
    }

    final splitPackage = package.split(':');
    final packageName = splitPackage[0];

    /// There shouldn't be more than one `:` in the package information
    if (splitPackage.length > 2) {
      usageException('Invalid package and version constraint: $package');
    }

    /// We want to allow for [constraint] to take on a `null` value here to
    /// preserve the fact that the user did not specify a constraint.
    VersionConstraint? constraint;

    try {
      constraint = splitPackage.length == 2
          ? VersionConstraint.parse(splitPackage[1])
          : null;
    } on FormatException catch (e) {
      usageException('Invalid version constraint: ${e.message}');
    }

    /// The package to be added.
    late final PackageRef ref;
    final path = this.path;
    if (hasGitOptions) {
      final gitUrl = this.gitUrl;
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
          ref: gitRef,
          path: gitPath,
        ),
      );
    } else if (path != null) {
      ref = PackageRef(
          packageName, PathDescription(p.absolute(path), p.isRelative(path)));
    } else if (sdk != null) {
      ref = cache.sdk.parseRef(packageName, sdk);
    } else {
      ref = PackageRef(
        packageName,
        HostedDescription(
          packageName,
          hostUrl ?? cache.hosted.defaultUrl,
        ),
      );
    }
    return _ParseResult(ref, constraint);
  }

  /// Writes the changes to the pubspec file.
  void _updatePubspec(List<PackageId> resultPackages,
      List<_ParseResult> updates, bool isDevelopment) {
    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));
    log.io('Reading ${entrypoint.pubspecPath}.');
    log.fine('Contents:\n$yamlEditor');

    final dependencyKey = isDevelopment ? 'dev_dependencies' : 'dependencies';

    for (final update in updates) {
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
              containingDir: entrypoint.root.dir,
              languageVersion: entrypoint.root.pubspec.languageVersion),
          if (description is HostedDescription || constraint != null)
            'version': versionConstraintString
        };
      }
      final packagePath = [dependencyKey, name];

      if (yamlEditor.parseAt(
            [dependencyKey],
            orElse: () => YamlScalar.wrap(null),
          ).value ==
          null) {
        // Insert dependencyKey: {} if it did not exist.
        yamlEditor.update([dependencyKey], {});
      }
      yamlEditor.update(packagePath, pubspecInformation);

      /// Remove the package from dev_dependencies if we are adding it to
      /// dependencies. Refer to [_addPackageToPubspec] for additional discussion.
      if (!isDevelopment) {
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

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}

class _ParseResult {
  PackageRef ref;
  VersionConstraint? constraint;
  _ParseResult(this.ref, this.constraint);
}
