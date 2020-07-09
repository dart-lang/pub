import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../exceptions.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
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

  bool get isDevelopment => argResults['development'];

  AddCommand() {
    argParser.addFlag('development',
        abbr: 'd',
        negatable: false,
        help: 'Adds packages to the development dependencies instead.');
  }

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be added.');
    }
    final packages = parseVersionConstraints(argResults.rest);

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
      Pubspec original, Map<String, VersionConstraint> newDependencies) {
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
      Pubspec original, Map<String, VersionConstraint> newDependencies) {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(newDependencies, 'newDependencies');

    final dependencies = [...original.dependencies.values];
    final devDependencies = original.devDependencies.values;
    final devDependencyNames =
        devDependencies.map((devDependency) => devDependency.name);

    for (var entry in newDependencies.entries) {
      final packageName = entry.key;

      if (devDependencyNames.contains(packageName)) {
        log.warning('$packageName is already in dev-dependencies. '
            'Please remove existing entry before adding it to dependencies');

        continue;
      }

      final packageConstraint = entry.value ?? VersionConstraint.any;

      final newDependency = PackageRange(
          packageName, cache.sources['hosted'], packageConstraint, packageName);

      dependencies.add(newDependency);
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
      Pubspec original, Map<String, VersionConstraint> newDevDependencies) {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(newDevDependencies, 'newDevDependencies');

    final dependencies = original.dependencies.values;
    final dependencyNames = dependencies.map((dependency) => dependency.name);
    final devDependencies = [...original.dependencies.values];

    for (var entry in newDevDependencies.entries) {
      final packageName = entry.key;

      if (dependencyNames.contains(packageName)) {
        log.warning('$packageName is already in dependencies. '
            'Please remove existing entry before adding it to dev-dependencies');

        continue;
      }

      final packageConstraint = entry.value ?? VersionConstraint.any;

      final newDevDependency = PackageRange(
          packageName, cache.sources['hosted'], packageConstraint, packageName);

      devDependencies.add(newDevDependency);
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

  /// Parse package name and [VersionConstraint] from [packages].
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
  /// retry:any
  /// ```
  Map<String, VersionConstraint> parseVersionConstraints(
      Iterable<String> packages) {
    ArgumentError.checkNotNull(packages, 'packages');

    final result = <String, VersionConstraint>{};

    for (var package in packages) {
      const delimiter = ':';
      final splitPackage = package.split(delimiter);

      if (splitPackage.length > 2) {
        usageException('Invalid package and version constraint: $package');
      }

      var packageName = package;
      VersionConstraint constraint;

      if (splitPackage.length == 2) {
        packageName = splitPackage[0];
        constraint = VersionConstraint.parse(splitPackage[1]);
      }

      result[packageName] = constraint;
    }

    return result;
  }

  /// Writes the changes to the pubspec file
  void _updatePubspec(
      SolveResult result, Map<String, VersionConstraint> packages) {
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

    for (var package in packages.entries) {
      final packageName = package.key;
      final packagePath = [dependencyKey, packageName];

      if (package.value == null) {
        yamlEditor.assign(packagePath, '^${finalPackages[packageName]}');
      } else {
        yamlEditor.assign(packagePath, package.value.toString());
      }
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}
