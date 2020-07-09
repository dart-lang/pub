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
  @override
  bool get isOffline => argResults['offline'];

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
    final packages = parsePackageRanges(argResults.rest);

    /// Perform version resolution in-memory.
    var updatedPubSpec =
        _addPackagesToPubspec(entrypoint.root.pubspec, packages);
    var result = await resolveVersions(
      SolveType.GET,
      cache,
      Package.inMemory(updatedPubSpec),
    );

    /// Update the pubspec.
    _updatePubspec(result, packages);

    /// Run get once we have successfully updated the pubspec
    await runner.run(['get']);
  }

  /// Creates a new in-memory [Pubspec] by adding [newDependencies] to
  /// [original].
  /// TODO(walnut): allow package:any
  Pubspec _addPackagesToPubspec(
      Pubspec original, Iterable<PackageRange> newDependencies) {
    if (isDevelopment) {
      return _addPackagesToNormalDependencies(original, newDependencies);
    }

    return _addPackagesToDevelopmentDependencies(original, newDependencies);
  }

  /// TODO
  Pubspec _addPackagesToNormalDependencies(
      Pubspec original, Iterable<PackageRange> newDependencies) {
    final dependencies = [...original.dependencies.values];
    final devDependencies = original.devDependencies.values;
    final devDependencyNames =
        devDependencies.map((devDependency) => devDependency.name);

    for (var newDependency in newDependencies) {
      if (devDependencyNames.contains(newDependency.name)) {
        log.warning('${newDependency.name} is already in dev-dependencies. '
            'Please remove existing entry before adding it to dependencies');

        continue;
      }

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

  // TODO
  Pubspec _addPackagesToDevelopmentDependencies(
      Pubspec original, Iterable<PackageRange> newDevDependencies) {
    final dependencies = original.dependencies.values;
    final dependencyNames = dependencies.map((dependency) => dependency.name);
    final devDependencies = [...original.dependencies.values];

    for (var newDevDependency in newDevDependencies) {
      if (dependencyNames.contains(newDevDependency.name)) {
        log.warning('${newDevDependency.name} is already in dependencies. '
            'Please remove existing entry before adding it to dev-dependencies');

        continue;
      }

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

  /// Parse [PackageRange] from [packages].
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
  Iterable<PackageRange> parsePackageRanges(Iterable<String> packages) {
    final newDependencies = packages.map((package) {
      const delimiter = ':';
      final splitPackage = package.split(delimiter);

      if (splitPackage.length > 2) {
        usageException('Invalid package and version constraint: $package');
      }

      var packageName = package;
      var constraint = VersionConstraint.any;

      if (splitPackage.length == 2) {
        packageName = splitPackage[0];
        constraint = VersionConstraint.parse(splitPackage[1]);
      }

      return PackageRange(
          packageName, cache.sources['hosted'], constraint, packageName);
    });
    return newDependencies;
  }

  /// Writes the changes to the pubspec file
  void _updatePubspec(SolveResult result, Iterable<PackageRange> packages) {
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

      if (package.constraint == VersionConstraint.any) {
        yamlEditor.assign(packagePath, '^${finalPackages[packageName]}');
      } else {
        yamlEditor.assign(packagePath, package.constraint.toString());
      }
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}
