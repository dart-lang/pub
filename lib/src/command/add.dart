// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../solver.dart';
import '../utils.dart';

/// Handles the `add` pub command. Adds dependencies to `pubspec.yaml`.
class AddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description => 'Add a dependency to the current package.';
  @override
  String get invocation => 'pub add <package> [options]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-add';

  bool get isDevelopment => argResults['dev'];
  String get gitUrl => argResults['git-url'];
  String get gitPath => argResults['git-path'];
  String get gitRef => argResults['git-ref'];
  String get hostUrl => argResults['hosted-url'];
  String get path => argResults['path'];

  AddCommand() {
    argParser.addFlag('dev',
        abbr: 'd',
        negatable: false,
        help: 'Adds packages to the development dependencies instead.');

    argParser.addOption('git-url', help: 'Git URL of the package');
    argParser.addOption('git-ref',
        help: 'Git branch or commit to be retrieved');
    argParser.addOption('git-path', help: 'Path of git package');
    argParser.addOption('hosted-url', help: 'URL of package host server');
    argParser.addOption('path', help: 'Local path');

    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Precompile executables in immediate dependencies.');
  }

  bool get hasGitOptions => gitUrl != null || gitRef != null || gitPath != null;
  bool get hasHostOptions => hostUrl != null;

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be added.');
    }

    if ((path != null && hasGitOptions) ||
        (hasGitOptions && hasHostOptions) ||
        (hasHostOptions && path != null)) {
      usageException('Packages must either be a git, hosted, or path package.');
    }

    final packageInformation = _parsePackage(argResults.rest.first);
    final package = packageInformation.first;

    /// Perform version resolution in-memory.
    final updatedPubSpec =
        await _addPackageToPubspec(entrypoint.root.pubspec, package);
    final solveResult = await resolveVersions(
        SolveType.GET, cache, Package.inMemory(updatedPubSpec));

    final resultPackage = solveResult.packages
        .firstWhere((packageId) => packageId.name == package.name);

    /// Assert that [resultPackage] is within the original user's expectations.
    if (package.constraint != null &&
        !package.constraint.allows(resultPackage.version)) {
      dataError('${package.name} resolved to ${resultPackage.version} which '
          'does not match the input ${package.constraint}! Exiting.');
    }

    /// Update the pubspec.
    _updatePubspec(resultPackage, packageInformation);

    await Entrypoint.current(cache).acquireDependencies(SolveType.GET,
        dryRun: argResults['dry-run'], precompile: argResults['precompile']);

    if (isOffline) {
      log.warning('Warning: Packages added when offline may not resolve to '
          'the latest versions of your dependencies.');
    }
  }

  /// Creates a new in-memory [Pubspec] by adding [package] to [original].
  Future<Pubspec> _addPackageToPubspec(
      Pubspec original, PackageRange package) async {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(package, 'package');

    final dependencies = [...original.dependencies.values];
    var devDependencies = [...original.devDependencies.values];

    if (isDevelopment) {
      final dependencyNames = dependencies.map((dependency) => dependency.name);

      /// If package is originally in dependencies and we wish to add it to
      /// dev_dependencies, this is a redundant change, and we should not
      /// remove the package from dependencies, since it might cause the user's
      /// code to break.
      if (dependencyNames.contains(package.name)) {
        usageException('${package.name} is already in dependencies. '
            'Please remove existing entry before adding it to dev_dependencies');
      }

      devDependencies.add(package);
    } else {
      final devDependencyNames =
          devDependencies.map((devDependency) => devDependency.name);

      /// If package is originally in dev_dependencies and we wish to add it to
      /// dependencies, we remove the package from dev_dependencies, since it is
      /// now redundant.
      if (devDependencyNames.contains(package.name)) {
        log.message('${package.name} was found in dev_dependencies. '
            'Removing ${package.name} and adding it to dependencies instead.');
        devDependencies =
            devDependencies.where((d) => d.name != package.name).toList();
      }

      dependencies.add(package);
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

  /// Parse [pacakge] to return the corresponding [PackageRange], as well as its
  /// representation in `pubspec.yaml`.
  ///
  /// [package] must be written in the format
  /// `<package-name>[:<version-constraint>]`, where quotations should be used
  /// if necessary.
  ///
  /// Examples:
  /// ```bash
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
  /// If both `--path` and any of the `--git-<option>` options are defined,
  /// a [PackageParseError] will be thrown.
  ///
  /// If any of the other git options are defined when `--git-url` is not
  /// defined, an error will be thrown.
  Pair<PackageRange, dynamic> _parsePackage(String package) {
    ArgumentError.checkNotNull(package, 'package');

    PackageRange packageRange;
    dynamic pubspecInformation;

    if (hasGitOptions) {
      dynamic git;

      /// Process the git options to return the simplest representation to be
      /// added to the pubspec.
      if (gitRef == null && gitPath == null) {
        git = gitUrl;
      } else {
        git = {'url': gitUrl, 'ref': gitRef, 'path': gitPath};
        git.removeWhere((key, value) => value == null);
      }

      packageRange = cache.sources['git']
          .parseRef(package, git)
          .withConstraint(VersionRange());
      pubspecInformation = {'git': git};
    } else if (path != null) {
      packageRange = cache.sources['path']
          .parseRef(package, path, containingPath: entrypoint.pubspecPath)
          .withConstraint(VersionRange());
      pubspecInformation = {'path': path};
    } else {
      const delimiter = ':';
      final splitPackage = package.split(delimiter);
      final packageName = splitPackage[0];
      final hostInfo =
          hasHostOptions ? {'url': hostUrl, 'name': packageName} : null;

      /// There shouldn't be more than one `:` in the package information
      if (splitPackage.length > 2) {
        throw FormatException(
            'Invalid package and version constraint: $package');
      }

      /// We want to allow for [constraint] to take on a `null` value here to
      /// preserve the fact that the user did not specify a constraint.
      final constraint = splitPackage.length == 2
          ? VersionConstraint.parse(splitPackage[1])
          : null;

      if (hostInfo == null) {
        pubspecInformation = constraint?.toString();
      } else if (constraint == null) {
        pubspecInformation = {'hosted': hostInfo};
      } else {
        pubspecInformation = {
          'hosted': hostInfo,
          'version': constraint.toString()
        };
      }

      packageRange = PackageRange(packageName, cache.sources['hosted'],
          constraint ?? VersionConstraint.any, hostInfo ?? packageName);
    }

    return Pair(packageRange, pubspecInformation);
  }

  /// Writes the changes to the pubspec file.
  void _updatePubspec(
      PackageId resultPackage, Pair<PackageRange, dynamic> packageInformation) {
    ArgumentError.checkNotNull(resultPackage, 'resultPackage');
    ArgumentError.checkNotNull(packageInformation, 'pubspecInformation');

    final package = packageInformation.first;
    final pubspecInformation = packageInformation.last;

    final dependencyKey = isDevelopment ? 'dev_dependencies' : 'dependencies';
    final packagePath = [dependencyKey, package.name];

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));

    if (pubspecInformation == null) {
      yamlEditor.update(packagePath, '^${resultPackage.version}');
    } else {
      yamlEditor.update(packagePath, pubspecInformation);
    }

    if (!isDevelopment &&
        yamlEditor.parseAt(['dev_dependencies', package.name],
                orElse: () => null) !=
            null) {
      yamlEditor.remove(['dev_dependencies', package.name]);
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}
