import 'package:pub_semver/pub_semver.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../command.dart';
import '../exceptions.dart';
import '../io.dart';
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

  /// TODO(walnut): ensure that the flags are appropriately handled
  AddCommand() {
    argParser.addFlag('offline',
        help: 'Use cached packages instead of accessing the network.');

    argParser.addFlag('development',
        abbr: 'd',
        negatable: false,
        help: 'Adds packages to the development dependencies instead.');

    argParser.addFlag('dry-run',
        abbr: 'n',
        negatable: false,
        help: "Report what dependencies would change but don't change any.");

    argParser.addFlag('precompile',
        help: 'Precompile executables in immediate dependencies.');
  }

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      usageException('Must specify a package to be added.');
    }

    final dependencyKey =
        argResults['development'] ? 'dev_dependencies' : 'dependencies';

    final packages = parsePackageRanges(argResults.rest);

    /// Perform version resolution in-memory.
    var updatedPubSpec = _addPackagesToPubspec(
        entrypoint.root.pubspec, packages, argResults['development']);
    var result = await resolveVersions(
      SolveType.GET,
      cache,
      Package.inMemory(updatedPubSpec),
    );

    /// Update the pubspec.
    _updatePubspec(result, packages, dependencyKey);

    /// Run get once we have successfully updated the pubspec
    await runner.run(['get']);
  }

  /// Creates a new in-memory [Pubspec] by adding [newDependencies] to
  /// [original].
  Pubspec _addPackagesToPubspec(Pubspec original,
      Iterable<PackageRange> newDependencies, bool development) {
    var dependencies = !development
        ? [...original.dependencies.values, ...newDependencies]
        : original.dependencies.values;
    var devDependencies = development
        ? [...original.dependencies.values, ...newDependencies]
        : original.devDependencies.values;

    return Pubspec(
      original.name,
      version: original.version,
      sdkConstraints: original.sdkConstraints,
      dependencies: dependencies,
      devDependencies: devDependencies,
      dependencyOverrides: [],
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
  void _updatePubspec(SolveResult result, Iterable<PackageRange> packages,
      String dependencyKey) {
    if (entrypoint.pubspecPath == null) {
      throw FileException(
          // Make the package dir absolute because for the entrypoint it'll just
          // be ".", which may be confusing.
          'Could not find a file named "pubspec.yaml" in '
          '"${canonicalize('.')}".',
          entrypoint.pubspecPath);
    }

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
