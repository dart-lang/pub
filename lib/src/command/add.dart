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

    final packages = argResults.rest;

    /// Step 1: Run resolutions on in-memory mutations.
    var updatedPubSpec = _addPackagesToPubspec(
        entrypoint.root.pubspec, packages, argResults['development']);
    print(updatedPubSpec.dependencies);

    var result = await resolveVersions(
      SolveType.GET,
      cache,
      Package.inMemory(updatedPubSpec),
    );

    _updatePubspec(result, packages, dependencyKey);

    await runner.run(['get']);
  }

  Pubspec _addPackagesToPubspec(
      Pubspec original, List<String> packages, bool development) {
    final newDependencies = packages.map((package) {
      // TODO(walnut): break down to version constraints.
      return PackageRange(
          package, cache.sources['hosted'], VersionConstraint.any, package);
    });

    return Pubspec(
      original.name,
      version: original.version,
      sdkConstraints: original.sdkConstraints,
      dependencies: [...original.dependencies.values, ...newDependencies],
      devDependencies: original.devDependencies.values,
      dependencyOverrides: [],
    );
  }

  void _updatePubspec(
      SolveResult result, List<String> packages, String dependencyKey) {
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
      yamlEditor.assign([dependencyKey, package], '^${finalPackages[package]}');
    }

    /// Windows line endings are already handled by [yamlEditor]
    writeTextFile(entrypoint.pubspecPath, yamlEditor.toString());
  }
}
