// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../exceptions.dart';
import '../exit_codes.dart' as exit_codes;
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_info.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../solver.dart';
import '../utils.dart';

/// Handles the `add` pub command.
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
  }

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be added.');
    }

    final hasGitOptions = gitUrl != null || gitRef != null || gitPath != null;
    final hasHostOptions = hostUrl != null;

    if ((path != null && hasGitOptions) ||
        (hasGitOptions && hasHostOptions) ||
        (hasHostOptions && path != null)) {
      usageException('Packages must either be a git, hosted, or path package.');
    }

    final package = _parsePackage(argResults.rest.first);

    /// Perform version resolution in-memory.
    final updatedPubSpec =
        await _addPackagesToPubspec(entrypoint.root.pubspec, package);
    final solveResult = await resolveVersions(
        SolveType.GET, cache, Package.inMemory(updatedPubSpec));

    final resultPackage =
        await _getAndAssertResultPackage(solveResult, package);

    /// Update the pubspec.
    _updatePubspec(resultPackage, package);

    /// Run pub get once we have successfully updated the pubspec
    await runner.run(['get']);
  }

  /// Creates a new in-memory [Pubspec] by adding [package] to [original].
  Future<Pubspec> _addPackagesToPubspec(
      Pubspec original, PackageInfo package) async {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(package, 'package');

    final dependencies = [...original.dependencies.values];
    var devDependencies = [...original.devDependencies.values];

    if (isDevelopment) {
      final dependencyNames = dependencies.map((dependency) => dependency.name);

      if (dependencyNames.contains(package.name)) {
        log.message('${package.name} is already in dependencies. '
            'Please remove existing entry before adding it to dev_dependencies');
        await flushThenExit(exit_codes.SUCCESS);
      }

      devDependencies.add(package.toPackageRange(cache));
    } else {
      final devDependencyNames =
          devDependencies.map((devDependency) => devDependency.name);

      if (devDependencyNames.contains(package.name)) {
        log.message('${package.name} was found in dev_dependencies. '
            'Removing ${package.name} and adding it to dependencies instead.');
        devDependencies =
            devDependencies.takeWhile((d) => d.name != package.name).toList();
      }

      dependencies.add(package.toPackageRange(cache));
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

  /// Parse [PackageInfo] from [package].
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
  PackageInfo _parsePackage(String package) {
    ArgumentError.checkNotNull(package, 'packages');

    var git = <String, String>{};
    if (gitUrl != null) git['url'] = gitUrl;
    if (gitRef != null) git['ref'] = gitRef;
    if (gitPath != null) git['path'] = gitPath;
    if (git.isEmpty) git = null;

    Map<String, String> hostInfo;
    if (hostUrl != null) hostInfo = {'url': hostUrl};

    PackageInfo parsedPackage;

    try {
      parsedPackage = PackageInfo.from(package,
          path: path,
          git: git,
          pubspecPath: entrypoint.pubspecPath,
          hostInfo: hostInfo);
    } on PackageParseException catch (exception) {
      usageException(exception.message);
    }

    return parsedPackage;
  }

  /// Retrieves the result of version resolution on [package], and assert that
  /// it is within the original user's expectations, throwing a [DataError]
  /// otherwise.
  Future<PackageId> _getAndAssertResultPackage(
      SolveResult result, PackageInfo package) async {
    ArgumentError.checkNotNull(result, 'result');
    ArgumentError.checkNotNull(package, 'package');

    /// The `orElse` scenario should not happen because it would have been
    /// discovered in the version resolution process.
    final resultPackage = result.packages
        .firstWhere((packageId) => packageId.name == package.name);

    if (package is HostedPackageInfo &&
        package.constraint != null &&
        !package.constraint.allows(resultPackage.version)) {
      dataError('${package.name} resolved to ${resultPackage.version} which '
          'does not match the input ${package.constraint}! Exiting.');
    }

    return resultPackage;
  }

  /// Writes the changes to the pubspec file
  void _updatePubspec(PackageId resultPackage, PackageInfo package) {
    ArgumentError.checkNotNull(resultPackage, 'resultPackage');
    ArgumentError.checkNotNull(package, 'package');

    if (entrypoint.pubspecPath == null) {
      throw FileException(
          // Make the package dir absolute because for the entrypoint it'll just
          // be ".", which may be confusing.
          'Could not find a file named "pubspec.yaml" in '
          '"${canonicalize('.')}".',
          entrypoint.pubspecPath);
    }

    final dependencyKey = isDevelopment ? 'dev_dependencies' : 'dependencies';
    final packagePath = [dependencyKey, package.name];

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));

    if (package.pubspecInfo == null) {
      yamlEditor.update(packagePath, '^${resultPackage.version}');
    } else {
      yamlEditor.update(packagePath, package.pubspecInfo);
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
