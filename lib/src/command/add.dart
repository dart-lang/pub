// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../exceptions.dart';
import '../io.dart';
import '../package.dart';
import '../package_info.dart';
import '../pubspec.dart';
import '../solver.dart';

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
  String get hostName => argResults['host-name'];
  String get hostUrl => argResults['host-url'];
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
    argParser.addOption('host-name', help: 'Name of host package');
    argParser.addOption('host-url', help: 'URL of package host server');
    argParser.addOption('path', help: 'Local path');
  }

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be added.');
    }

    final hasGitOptions = gitUrl != null || gitRef != null || gitPath != null;
    final hasHostOptions = hostName != null || hostUrl != null;

    if ((path != null && hasGitOptions) ||
        (hasGitOptions && hasHostOptions) ||
        (hasHostOptions && path != null)) {
      usageException('Packages must either be a git, hosted, or path package.');
    }

    final packages = _parsePackages(argResults.rest);

    /// Perform version resolution in-memory.
    var updatedPubSpec =
        _addPackagesToPubspec(entrypoint.root.pubspec, packages);
    var result = await resolveVersions(
        SolveType.GET, cache, Package.inMemory(updatedPubSpec));

    /// Update the pubspec.
    _updatePubspec(result, packages);

    /// Run pub get once we have successfully updated the pubspec
    await runner.run(['get']);
  }

  /// Creates a new in-memory [Pubspec] by adding the packages specified in
  /// [newDependencies] to [original].
  Pubspec _addPackagesToPubspec(
      Pubspec original, Iterable<PackageInfo> newDependencies) {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(newDependencies, 'newDependencies');

    if (isDevelopment) {
      return _addPackagesToDevelopmentDependencies(original, newDependencies);
    }
    return _addPackagesToNormalDependencies(original, newDependencies);
  }

  /// Creates a new in-memory [Pubspec] by adding the packages specified in
  /// [newDependencies] to [original]'s normal dependencies.
  Pubspec _addPackagesToNormalDependencies(
      Pubspec original, Iterable<PackageInfo> newDependencies) {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(newDependencies, 'newDependencies');

    final dependencies = [...original.dependencies.values];
    final devDependencies = original.devDependencies.values;
    final devDependencyNames =
        devDependencies.map((devDependency) => devDependency.name);

    for (var package in newDependencies) {
      final packageName = package.name;

      if (devDependencyNames.contains(packageName)) {
        usageException('$packageName is already in dev_dependencies. '
            'Please remove existing entry before adding it to dependencies');
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

  /// Creates a new in-memory [Pubspec] by adding the packages specified in
  /// [newDependencies] to [original]'s development dependencies.
  Pubspec _addPackagesToDevelopmentDependencies(
      Pubspec original, Iterable<PackageInfo> newDevDependencies) {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(newDevDependencies, 'newDevDependencies');

    final dependencies = original.dependencies.values;
    final dependencyNames = dependencies.map((dependency) => dependency.name);
    final devDependencies = [...original.dependencies.values];

    for (var package in newDevDependencies) {
      final packageName = package.name;

      if (dependencyNames.contains(packageName)) {
        usageException('$packageName is already in dependencies. '
            'Please remove existing entry before adding it to dev_dependencies');
      }

      devDependencies.add(package.toPackageRange(cache));
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

  /// Parse [PackageInfo] from [packages].
  ///
  /// Each package in [packages] must be written in the format
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
  Iterable<PackageInfo> _parsePackages(Iterable<String> packages) {
    ArgumentError.checkNotNull(packages, 'packages');

    final parsedPackages = packages.map((package) {
      PackageInfo packageInfo;

      var git = <String, String>{};
      if (gitUrl != null) git['url'] = gitUrl;
      if (gitRef != null) git['ref'] = gitRef;
      if (gitPath != null) git['path'] = gitPath;
      if (git.isEmpty) git = null;

      var hostInfo = <String, String>{};
      if (hostName != null) hostInfo['name'] = hostName;
      if (hostUrl != null) hostInfo['url'] = hostUrl;
      if (hostInfo.isEmpty) hostInfo = null;

      try {
        packageInfo = PackageInfo.from(package,
            path: path,
            git: git,
            pubspecPath: entrypoint.pubspecPath,
            hostInfo: hostInfo);
      } on PackageParseException catch (exception) {
        usageException(exception.message);
      }

      return packageInfo;
    });

    return parsedPackages;
  }

  /// Writes the changes to the pubspec file
  void _updatePubspec(SolveResult result, Iterable<PackageInfo> packages) {
    ArgumentError.checkNotNull(result, 'result');
    ArgumentError.checkNotNull(packages, 'packages');

    if (entrypoint.pubspecPath == null) {
      throw FileException(
          // Make the package dir absolute because for the entrypoint it'll just
          // be ".", which may be confusing.
          'Could not find a file named "pubspec.yaml" in '
          '"${canonicalize('.')}".',
          entrypoint.pubspecPath);
    }

    final dependencyKey = isDevelopment ? 'dev_dependencies' : 'dependencies';

    final yamlEditor = YamlEditor(readTextFile(entrypoint.pubspecPath));

    final finalPackages = <String, Version>{};
    for (var package in result.packages) {
      finalPackages[package.name] = package.version;
    }

    for (var package in packages) {
      final packageName = package.name;
      final packagePath = [dependencyKey, packageName];

      if (package.pubspecInfo == null) {
        yamlEditor.update(packagePath, '^${finalPackages[packageName]}');
      } else {
        yamlEditor.update(packagePath, package.pubspecInfo);
      }
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}
