// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../exceptions.dart';
import '../git.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../solver.dart';
import '../utils.dart';
import '../yaml_edit/editor.dart';

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
  String get description => 'Add a dependency to pubspec.yaml.';
  @override
  String get argumentsDescription => '<package>[:<constraint>] [options]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-add';
  @override
  bool get isOffline => argResults['offline'];

  bool get isDev => argResults['dev'];
  bool get isDryRun => argResults['dry-run'];
  String get gitUrl => argResults['git-url'];
  String get gitPath => argResults['git-path'];
  String get gitRef => argResults['git-ref'];
  String get hostUrl => argResults['hosted-url'];
  String get path => argResults['path'];
  String get sdk => argResults['sdk'];

  bool get hasGitOptions => gitUrl != null || gitRef != null || gitPath != null;
  bool get hasHostOptions => hostUrl != null;

  AddCommand() {
    argParser.addFlag('dev',
        abbr: 'd',
        negatable: false,
        help: 'Adds package to the development dependencies instead.');

    argParser.addOption('git-url', help: 'Git URL of the package');
    argParser.addOption('git-ref',
        help: 'Git branch or commit to be retrieved');
    argParser.addOption('git-path', help: 'Path of git package in repository');
    argParser.addOption('hosted-url', help: 'URL of package host server');
    argParser.addOption('path', help: 'Local path');
    argParser.addOption('sdk', help: 'SDK source for package');

    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Precompile executables in immediate dependencies.');
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be added.');
    }

    final packageInformation = _parsePackage(argResults.rest.first);
    final package = packageInformation.first;

    /// Perform version resolution in-memory.
    final updatedPubSpec =
        await _addPackageToPubspec(entrypoint.root.pubspec, package);

    SolveResult solveResult;

    try {
      /// Use [SolveType.UPGRADE] to solve for the highest version of [package]
      /// in case [package] was already a transitive dependency. In the case
      /// where the user specifies a version constraint, this serves to ensure
      /// that a resolution exists before we update pubspec.yaml.
      solveResult = await resolveVersions(
          SolveType.UPGRADE, cache, Package.inMemory(updatedPubSpec));
    } on GitException {
      dataError('Unable to resolve package "${package.name}" with the given '
          'git parameters.');
    } on SolveFailure catch (e) {
      dataError(e.message);
    } on WrappedException catch (e) {
      /// [WrappedException]s may appear if an invalid [hostUrl] is passed in.
      dataError(e.message);
    }

    final resultPackage = solveResult.packages
        .firstWhere((packageId) => packageId.name == package.name);

    /// Assert that [resultPackage] is within the original user's expectations.
    if (package.constraint != null &&
        !package.constraint.allows(resultPackage.version)) {
      if (updatedPubSpec.dependencyOverrides != null &&
          updatedPubSpec.dependencyOverrides.isNotEmpty) {
        dataError(
            '"${package.name}" resolved to "${resultPackage.version}" which '
            'does not satisfy constraint "${package.constraint}". This could be '
            'caused by "dependency_overrides".');
      }
      dataError(
          '"${package.name}" resolved to "${resultPackage.version}" which '
          'does not satisfy constraint "${package.constraint}".');
    }

    if (isDryRun) {
      /// Even if it is a dry run, run `acquireDependencies` so that the user
      /// gets a report on the other packages that might change version due
      /// to this new dependency.
      final newRoot = Package.inMemory(updatedPubSpec);

      // TODO(jonasfj): Stop abusing Entrypoint.global for dry-run output
      await Entrypoint.global(newRoot, entrypoint.lockFile, cache,
              solveResult: solveResult)
          .acquireDependencies(
        SolveType.GET,
        dryRun: true,
        precompile: argResults['precompile'],
      );
    } else {
      /// Update the `pubspec.yaml` before calling [acquireDependencies] to
      /// ensure that the modification timestamp on `pubspec.lock` and
      /// `.dart_tool/package_config.json` is newer than `pubspec.yaml`,
      /// ensuring that [entrypoint.assertUptoDate] will pass.
      _updatePubspec(resultPackage, packageInformation, isDev);

      /// Create a new [Entrypoint] since we have to reprocess the updated
      /// pubspec file.
      await Entrypoint.current(cache).acquireDependencies(SolveType.GET,
          precompile: argResults['precompile']);
    }

    if (isOffline) {
      log.warning('Warning: Packages added when offline may not resolve to '
          'the latest compatible version available.');
    }
  }

  /// Creates a new in-memory [Pubspec] by adding [package] to the
  /// dependencies of [original].
  Future<Pubspec> _addPackageToPubspec(
      Pubspec original, PackageRange package) async {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(package, 'package');

    final dependencies = [...original.dependencies.values];
    var devDependencies = [...original.devDependencies.values];
    final dependencyNames = dependencies.map((dependency) => dependency.name);
    final devDependencyNames =
        devDependencies.map((devDependency) => devDependency.name);

    if (isDev) {
      /// TODO(walnut): Change the error message once pub upgrade --bump is
      /// released
      if (devDependencyNames.contains(package.name)) {
        dataError('"${package.name}" is already in "dev_dependencies". '
            'Use "pub upgrade ${package.name}" to upgrade to a later version!');
      }

      /// If package is originally in dependencies and we wish to add it to
      /// dev_dependencies, this is a redundant change, and we should not
      /// remove the package from dependencies, since it might cause the user's
      /// code to break.
      if (dependencyNames.contains(package.name)) {
        dataError('"${package.name}" is already in "dependencies". '
            'Use "pub remove ${package.name}" to remove it before adding it '
            'to "dev_dependencies"');
      }

      devDependencies.add(package);
    } else {
      /// TODO(walnut): Change the error message once pub upgrade --bump is
      /// released
      if (dependencyNames.contains(package.name)) {
        dataError('"${package.name}" is already in "dependencies". '
            'Use "pub upgrade ${package.name}" to upgrade to a later version!');
      }

      /// If package is originally in dev_dependencies and we wish to add it to
      /// dependencies, we remove the package from dev_dependencies, since it is
      /// now redundant.
      if (devDependencyNames.contains(package.name)) {
        log.message('"${package.name}" was found in dev_dependencies. '
            'Removing "${package.name}" and adding it to dependencies instead.');
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
  Pair<PackageRange, dynamic> _parsePackage(String package) {
    ArgumentError.checkNotNull(package, 'package');

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
          .firstWhere(argResults.wasParsed, orElse: () => null);
      if (conflictingFlag != null) {
        usageException(
            'Packages can only have one source, "pub add" flags "--$flag" and '
            '"--$conflictingFlag" are conflicting.');
      }
    }

    /// The package to be added, along with the user-defined package constraints
    /// if present.
    PackageRange packageRange;

    /// The entry to be added to the pubspec. Assigned dynamic because it can
    /// take on either a string for simple version constraints or a map for
    /// more complicated hosted/git options.
    dynamic pubspecInformation;

    final splitPackage = package.split(':');
    final packageName = splitPackage[0];

    /// There shouldn't be more than one `:` in the package information
    if (splitPackage.length > 2) {
      usageException('Invalid package and version constraint: $package');
    }

    /// We want to allow for [constraint] to take on a `null` value here to
    /// preserve the fact that the user did not specify a constraint.
    VersionConstraint constraint;

    try {
      constraint = splitPackage.length == 2
          ? VersionConstraint.parse(splitPackage[1])
          : null;
    } on FormatException catch (e) {
      usageException('Invalid version constraint: ${e.message}');
    }

    /// Determine the relevant [packageRange] and [pubspecInformation] depending
    /// on the type of package.
    if (hasGitOptions) {
      dynamic git;

      if (gitUrl == null) {
        usageException('The `--git-url` is required for git dependencies.');
      }

      /// Process the git options to return the simplest representation to be
      /// added to the pubspec.
      if (gitRef == null && gitPath == null) {
        git = gitUrl;
      } else {
        git = {'url': gitUrl, 'ref': gitRef, 'path': gitPath};
        git.removeWhere((key, value) => value == null);
      }

      packageRange = cache.sources['git']
          .parseRef(packageName, git)
          .withConstraint(constraint ?? VersionConstraint.any);
      pubspecInformation = {'git': git};
    } else if (path != null) {
      packageRange = cache.sources['path']
          .parseRef(packageName, path, containingPath: entrypoint.pubspecPath)
          .withConstraint(constraint ?? VersionConstraint.any);
      pubspecInformation = {'path': path};
    } else if (sdk != null) {
      packageRange = cache.sources['sdk']
          .parseRef(packageName, sdk)
          .withConstraint(constraint ?? VersionConstraint.any);
      pubspecInformation = {'sdk': sdk};
    } else {
      final hostInfo =
          hasHostOptions ? {'url': hostUrl, 'name': packageName} : null;

      if (hostInfo == null) {
        pubspecInformation = constraint?.toString();
      } else {
        pubspecInformation = {'hosted': hostInfo};
      }

      packageRange = PackageRange(packageName, cache.sources['hosted'],
          constraint ?? VersionConstraint.any, hostInfo ?? packageName);
    }

    if (pubspecInformation is Map && constraint != null) {
      /// We cannot simply assign the value of version since it is likely that
      /// [pubspecInformation] takes on the type
      /// [Map<String, Map<String, String>>]
      pubspecInformation = {
        ...pubspecInformation,
        'version': constraint.toString()
      };
    }

    return Pair(packageRange, pubspecInformation);
  }

  /// Writes the changes to the pubspec file.
  void _updatePubspec(PackageId resultPackage,
      Pair<PackageRange, dynamic> packageInformation, bool isDevelopment) {
    ArgumentError.checkNotNull(resultPackage, 'resultPackage');
    ArgumentError.checkNotNull(packageInformation, 'pubspecInformation');

    final package = packageInformation.first;
    var pubspecInformation = packageInformation.last;

    if ((sdk != null || hasHostOptions) &&
        pubspecInformation is Map &&
        pubspecInformation['version'] == null) {
      /// We cannot simply assign the value of version since it is likely that
      /// [pubspecInformation] takes on the type
      /// [Map<String, Map<String, String>>]
      pubspecInformation = {
        ...pubspecInformation,
        'version': '^${resultPackage.version}'
      };
    }

    final dependencyKey = isDevelopment ? 'dev_dependencies' : 'dependencies';
    final packagePath = [dependencyKey, package.name];

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));
    log.io('Reading ${entrypoint.pubspecPath}.');
    log.fine('Contents:\n$yamlEditor');

    /// Handle situations where the user might not have the dependencies or
    /// dev_dependencies map.
    if (yamlEditor.parseAt([dependencyKey], orElse: () => null)?.value ==
        null) {
      yamlEditor.update([dependencyKey],
          {package.name: pubspecInformation ?? '^${resultPackage.version}'});
    } else {
      yamlEditor.update(
          packagePath, pubspecInformation ?? '^${resultPackage.version}');
    }

    log.fine('Added ${package.name} to "$dependencyKey".');

    /// Remove the package from dev_dependencies if we are adding it to
    /// dependencies. Refer to [_addPackageToPubspec] for additional discussion.
    if (!isDevelopment) {
      final devDependenciesNode =
          yamlEditor.parseAt(['dev_dependencies'], orElse: () => null);

      if (devDependenciesNode is YamlMap &&
          devDependenciesNode.containsKey(package.name)) {
        if (devDependenciesNode.length == 1) {
          yamlEditor.remove(['dev_dependencies']);
        } else {
          yamlEditor.remove(['dev_dependencies', package.name]);
        }

        log.fine('Removed ${package.name} from "dev_dependencies".');
      }
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}
