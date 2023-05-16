// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:path/path.dart' as path;

import '../command.dart';
import '../command_runner.dart';
import '../entrypoint.dart';
import '../io.dart';
import '../lock_file.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../pubspec_utils.dart';
import '../solver.dart';
import '../source/git.dart';
import '../source/path.dart';
import '../source/sdk.dart' show SdkSource;
import '../system_cache.dart';
import '../utils.dart';

class OutdatedCommand extends PubCommand {
  @override
  String get name => 'outdated';
  @override
  String get description =>
      'Analyze your dependencies to find which ones can be upgraded.';
  @override
  String get argumentsDescription => '[options]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-outdated';

  /// Avoid showing spinning progress messages when not in a terminal, and
  /// when we are outputting machine-readable json.
  bool get _shouldShowSpinner =>
      terminalOutputForStdout && !asBool(argResults['json']);

  @override
  bool get takesArguments => false;

  OutdatedCommand() {
    argParser.addFlag(
      'dependency-overrides',
      defaultsTo: true,
      help: 'Show resolutions with `dependency_overrides`.',
    );

    argParser.addFlag(
      'dev-dependencies',
      defaultsTo: true,
      help: 'Take dev dependencies into account.',
    );

    argParser.addFlag(
      'json',
      help: 'Output the results using a json format.',
      negatable: false,
    );

    argParser.addOption(
      'mode',
      help: 'Highlight versions with PROPERTY.\n'
          'Only packages currently missing that PROPERTY will be included unless '
          '--show-all.',
      valueHelp: 'PROPERTY',
      allowed: ['outdated', 'null-safety'],
      defaultsTo: 'outdated',
      hide: true,
    );

    argParser.addFlag(
      'prereleases',
      help: 'Include prereleases in latest version.',
    );

    // Preserve for backwards compatibility.
    argParser.addFlag(
      'pre-releases',
      help: 'Alias of prereleases.',
      hide: true,
    );

    argParser.addFlag(
      'show-all',
      help: 'Include dependencies that are already fullfilling --mode.',
    );

    // Preserve for backwards compatibility.
    argParser.addFlag(
      'up-to-date',
      hide: true,
      help: 'Include dependencies that are already at the '
          'latest version. Alias of --show-all.',
    );
    argParser.addFlag(
      'transitive',
      help: 'Show transitive dependencies.',
    );
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
  }

  @override
  Future<void> runProtected() async {
    if (argResults['mode'] == 'null-safety') {
      dataError('''The `--mode=null-safety` option is no longer supported.
Consider using the Dart 2.19 sdk to migrate to null safety.''');
    }
    final mode = _OutdatedMode();

    final includeDevDependencies = asBool(argResults['dev-dependencies']);
    final includeDependencyOverrides =
        asBool(argResults['dependency-overrides']);
    if (asBool(argResults['json']) && argResults.wasParsed('transitive')) {
      usageException('Cannot specify both `--json` and `--transitive`\n'
          'The json report always includes transitive dependencies.');
    }

    final rootPubspec = includeDependencyOverrides
        ? entrypoint.root.pubspec
        : stripDependencyOverrides(entrypoint.root.pubspec);

    final upgradablePubspec = includeDevDependencies
        ? rootPubspec
        : stripDevDependencies(rootPubspec);

    final resolvablePubspec = await mode.resolvablePubspec(upgradablePubspec);

    late List<PackageId> upgradablePackages;
    late List<PackageId> resolvablePackages;
    late bool hasUpgradableResolution;
    late bool hasResolvableResolution;

    await log.spinner(
      'Resolving',
      () async {
        final upgradablePackagesResult = await _tryResolve(
          upgradablePubspec,
          cache,
          lockFile: entrypoint.lockFile,
        );
        hasUpgradableResolution = upgradablePackagesResult != null;
        upgradablePackages = upgradablePackagesResult ?? [];

        final resolvablePackagesResult = await _tryResolve(
          resolvablePubspec,
          cache,
          lockFile: entrypoint.lockFile,
        );
        hasResolvableResolution = resolvablePackagesResult != null;
        resolvablePackages = resolvablePackagesResult ?? [];
      },
      condition: _shouldShowSpinner,
    );

    // This list will be empty if there is no lock file.
    final currentPackages = entrypoint.lockFile.packages.values;

    /// The set of all dependencies (direct and transitive) that are in the
    /// closure of the non-dev dependencies from the root in at least one of
    /// the current, upgradable and resolvable resolutions.
    final nonDevDependencies = <String>{
      ...await _nonDevDependencyClosure(entrypoint.root, currentPackages),
      ...await _nonDevDependencyClosure(entrypoint.root, upgradablePackages),
      ...await _nonDevDependencyClosure(entrypoint.root, resolvablePackages),
    };

    Future<_PackageDetails> analyzeDependency(PackageRef packageRef) async {
      final name = packageRef.name;
      final current = entrypoint.lockFile.packages[name];

      final upgradable =
          upgradablePackages.firstWhereOrNull((id) => id.name == name);
      final resolvable =
          resolvablePackages.firstWhereOrNull((id) => id.name == name);

      // Find the latest version, and if it's overridden.
      var latestIsOverridden = false;
      PackageId? latest;
      // If not overridden in current resolution we can use this
      if (!entrypoint.root.pubspec.dependencyOverrides.containsKey(name)) {
        latest ??= await cache.getLatest(
          current?.toRef(),
          version: current?.version,
          allowPrereleases: prereleases,
        );
      }
      // If present as a dependency or dev_dependency we use this
      latest ??= await cache.getLatest(
        rootPubspec.dependencies[name]?.toRef(),
        allowPrereleases: prereleases,
      );
      latest ??= await cache.getLatest(
        rootPubspec.devDependencies[name]?.toRef(),
        allowPrereleases: prereleases,
      );
      // If not overridden and present in either upgradable or resolvable we
      // use this reference to find the latest
      if (!upgradablePubspec.dependencyOverrides.containsKey(name)) {
        latest ??= await cache.getLatest(
          upgradable?.toRef(),
          version: upgradable?.version,
          allowPrereleases: prereleases,
        );
      }
      if (!resolvablePubspec.dependencyOverrides.containsKey(name)) {
        latest ??= await cache.getLatest(
          resolvable?.toRef(),
          version: resolvable?.version,
          allowPrereleases: prereleases,
        );
      }
      // Otherwise, we might simply not have a latest, when a transitive
      // dependency is overridden the source can depend on which versions we
      // are picking. This is not a problem on `pub.dev` because it does not
      // allow 3rd party pub servers, but other servers might. Hence, we choose
      // to fallback to using the overridden source for latest.
      if (latest == null) {
        final id = current ?? upgradable ?? resolvable;
        latest ??= await cache.getLatest(
          id?.toRef(),
          version: id?.version,
          allowPrereleases: prereleases,
        );
        latestIsOverridden = true;
      }

      final packageStatus = await current?.source.status(
        current.toRef(),
        current.version,
        cache,
      );
      final discontinued =
          packageStatus == null ? false : packageStatus.isDiscontinued;
      final discontinuedReplacedBy = packageStatus?.discontinuedReplacedBy;

      return _PackageDetails(
        name,
        await _describeVersion(
          current,
          entrypoint.root.pubspec.dependencyOverrides.containsKey(name),
        ),
        await _describeVersion(
          upgradable,
          upgradablePubspec.dependencyOverrides.containsKey(name),
        ),
        await _describeVersion(
          resolvable,
          resolvablePubspec.dependencyOverrides.containsKey(name),
        ),
        await _describeVersion(
          latest,
          latestIsOverridden,
        ),
        _kind(name, entrypoint, nonDevDependencies),
        discontinued,
        discontinuedReplacedBy,
      );
    }

    final rows = <_PackageDetails>[];

    final visited = <String>{
      entrypoint.root.name,
    };
    // Add all dependencies from the lockfile.
    for (final id in [
      ...currentPackages,
      ...upgradablePackages,
      ...resolvablePackages
    ]) {
      if (!visited.add(id.name)) continue;
      rows.add(await analyzeDependency(id.toRef()));
    }

    if (!includeDevDependencies) {
      rows.removeWhere((r) => r.kind == _DependencyKind.dev);
    }

    rows.sort();

    final showAll =
        asBool(argResults['show-all']) || asBool(argResults['up-to-date']);
    if (asBool(argResults['json'])) {
      await _outputJson(
        rows,
        mode,
        showAll: showAll,
        includeDevDependencies: includeDevDependencies,
      );
    } else {
      await _outputHuman(
        rows,
        mode,
        useColors: canUseAnsiCodes,
        showAll: showAll,
        includeDevDependencies: includeDevDependencies,
        lockFileExists: fileExists(entrypoint.lockFilePath),
        hasDirectDependencies: rootPubspec.dependencies.values.any(
          // Test if it contains non-SDK dependencies
          (c) => c.source is! SdkSource,
        ),
        hasDevDependencies: rootPubspec.devDependencies.values.any(
          // Test if it contains non-SDK dependencies
          (c) => c.source is! SdkSource,
        ),
        showTransitiveDependencies: showTransitiveDependencies,
        hasUpgradableResolution: hasUpgradableResolution,
        hasResolvableResolution: hasResolvableResolution,
        directory: path.normalize(directory),
      );
    }
  }

  bool get showTransitiveDependencies {
    return asBool(argResults['transitive']);
  }

  late final bool prereleases = () {
    // First check if 'prereleases' was passed as an argument.
    // If that was not the case, check for use of the legacy spelling
    // 'pre-releases'.
    // Otherwise fall back to the default implied by the mode.
    if (argResults.wasParsed('prereleases')) {
      return asBool(argResults['prereleases']);
    }
    if (argResults.wasParsed('pre-releases')) {
      return asBool(argResults['pre-releases']);
    }
    return false;
  }();

  /// Retrieves the pubspec of package [name] in [version] from [source].
  ///
  /// Returns `null`, if given `null` as a convinience.
  Future<_VersionDetails?> _describeVersion(
    PackageId? id,
    bool isOverridden,
  ) async {
    if (id == null) {
      return null;
    }
    return _VersionDetails(
      await cache.describe(id),
      id,
      isOverridden,
    );
  }

  /// Computes the closure of the graph of dependencies (not including
  /// `dev_dependencies` from [root], given the package versions
  /// in [resolution].
  ///
  /// The [resolution] is allowed to be a partial (or empty) resolution not
  /// satisfying all the dependencies of [root].
  Future<Set<String>> _nonDevDependencyClosure(
    Package root,
    Iterable<PackageId> resolution,
  ) async {
    final nameToId = Map<String, PackageId>.fromIterable(
      resolution,
      key: (id) => asString(id.name),
    );

    final nonDevDependencies = <String>{root.name};
    final queue = [...root.dependencies.keys];

    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      if (!nonDevDependencies.add(name)) {
        continue;
      }

      final id = nameToId[name];
      if (id == null) {
        continue; // allow partial resolutions
      }
      final pubspec = await cache.describe(id);
      queue.addAll(pubspec.dependencies.keys);
    }

    return nonDevDependencies;
  }
}

/// Try to solve [pubspec] return [PackageId]s in the resolution or `null` if no
/// resolution was found.
Future<List<PackageId>?> _tryResolve(
  Pubspec pubspec,
  SystemCache cache, {
  LockFile? lockFile,
}) async {
  final solveResult = await tryResolveVersions(
    SolveType.upgrade,
    cache,
    Package.inMemory(pubspec),
    lockFile: lockFile,
  );

  return solveResult?.packages;
}

Future<void> _outputJson(
  List<_PackageDetails> rows,
  _Mode mode, {
  required bool showAll,
  required bool includeDevDependencies,
}) async {
  final markedRows =
      Map.fromIterables(rows, await mode.markVersionDetails(rows));
  if (!showAll) {
    rows.removeWhere((row) => markedRows[row]![0].asDesired);
  }
  if (!includeDevDependencies) {
    rows.removeWhere(
      (element) =>
          element.kind == _DependencyKind.dev ||
          element.kind == _DependencyKind.devTransitive,
    );
  }

  String kindString(_DependencyKind kind) {
    return {
          _DependencyKind.direct: 'direct',
          _DependencyKind.dev: 'dev',
        }[kind] ??
        'transitive';
  }

  log.message(
    JsonEncoder.withIndent('  ').convert(
      {
        'packages': [
          ...(rows..sort((a, b) => a.name.compareTo(b.name))).map(
            (packageDetails) => {
              'package': packageDetails.name,
              'kind': kindString(packageDetails.kind),
              'isDiscontinued': packageDetails.isDiscontinued,
              'current': markedRows[packageDetails]![0].toJson(),
              'upgradable': markedRows[packageDetails]![1].toJson(),
              'resolvable': markedRows[packageDetails]![2].toJson(),
              'latest': markedRows[packageDetails]![3].toJson(),
            },
          )
        ]
      },
    ),
  );
}

Future<void> _outputHuman(
  List<_PackageDetails> rows,
  _Mode mode, {
  required bool showAll,
  required bool useColors,
  required bool includeDevDependencies,
  required bool lockFileExists,
  required bool hasDirectDependencies,
  required bool hasDevDependencies,
  required bool showTransitiveDependencies,
  required bool hasUpgradableResolution,
  required bool hasResolvableResolution,
  required String directory,
}) async {
  final directoryDesc = directory == '.' ? '' : ' in $directory';
  log.message('${mode.explanation(directoryDesc)}\n');
  final markedRows =
      Map.fromIterables(rows, await mode.markVersionDetails(rows));

  List<_FormattedString> formatted(_PackageDetails package) => [
        _FormattedString(package.name),
        ...markedRows[package]!.map((m) => m.toHuman()),
      ];

  if (!showAll) {
    rows.removeWhere((row) => markedRows[row]![0].asDesired);
  }
  if (rows.isEmpty) {
    log.message(mode.foundNoBadText);
    return;
  }

  bool Function(_PackageDetails) hasKind(_DependencyKind kind) =>
      (row) => row.kind == kind;

  final directRows = rows.where(hasKind(_DependencyKind.direct)).map(formatted);
  final devRows = rows.where(hasKind(_DependencyKind.dev)).map(formatted);
  final transitiveRows =
      rows.where(hasKind(_DependencyKind.transitive)).map(formatted);
  final devTransitiveRows =
      rows.where(hasKind(_DependencyKind.devTransitive)).map(formatted);

  final formattedRows = <List<_FormattedString>>[
    ['Package Name', 'Current', 'Upgradable', 'Resolvable', 'Latest']
        .map((s) => _format(s, log.bold))
        .toList(),
    if (hasDirectDependencies) ...[
      [
        if (directRows.isEmpty)
          _format('\ndirect dependencies: ${mode.allGood}', log.bold)
        else
          _format('\ndirect dependencies:', log.bold)
      ],
      ...directRows,
    ],
    if (includeDevDependencies && hasDevDependencies) ...[
      [
        if (devRows.isEmpty)
          _format('\ndev_dependencies: ${mode.allGood}', log.bold)
        else
          _format('\ndev_dependencies:', log.bold)
      ],
      ...devRows,
    ],
    if (showTransitiveDependencies) ...[
      if (transitiveRows.isNotEmpty)
        [_format('\ntransitive dependencies:', log.bold)],
      ...transitiveRows,
      if (includeDevDependencies) ...[
        if (devTransitiveRows.isNotEmpty)
          [_format('\ntransitive dev_dependencies:', log.bold)],
        ...devTransitiveRows,
      ],
    ],
  ];

  final columnWidths = <int, int>{};
  for (var i = 0; i < formattedRows.length; i++) {
    if (formattedRows[i].length > 1) {
      for (var j = 0; j < formattedRows[i].length; j++) {
        final currentMaxWidth = columnWidths[j] ?? 0;
        columnWidths[j] = max(
          formattedRows[i][j].computeLength(useColors: useColors),
          currentMaxWidth,
        );
      }
    }
  }

  for (final row in formattedRows) {
    final b = StringBuffer();
    for (var j = 0; j < row.length; j++) {
      b.write(row[j].formatted(useColors: useColors));
      b.write(
        ' ' *
            ((columnWidths[j]! + 2) -
                row[j].computeLength(useColors: useColors)),
      );
    }
    log.message(b.toString());
  }

  var upgradable = rows.where(
    (row) {
      final current = row.current;
      final upgradable = row.upgradable;
      return current != null &&
          upgradable != null &&
          current < upgradable &&
          // Include transitive only, if we show them
          (showTransitiveDependencies ||
              hasKind(_DependencyKind.direct)(row) ||
              hasKind(_DependencyKind.dev)(row));
    },
  ).length;

  var notAtResolvable = rows.where(
    (row) {
      final current = row.current;
      final upgradable = row.upgradable;
      final resolvable = row.resolvable;
      return (current != null || !lockFileExists) &&
          resolvable != null &&
          upgradable != null &&
          upgradable < resolvable &&
          // Include transitive only, if we show them
          (showTransitiveDependencies ||
              hasKind(_DependencyKind.direct)(row) ||
              hasKind(_DependencyKind.dev)(row));
    },
  ).length;

  if (!hasUpgradableResolution || !hasResolvableResolution) {
    log.message(mode.noResolutionText);
  } else if (lockFileExists) {
    if (upgradable != 0) {
      if (upgradable == 1) {
        log.message('\n1 upgradable dependency is locked (in pubspec.lock) to '
            'an older version.\n'
            'To update it, use `$topLevelProgram pub upgrade`.');
      } else {
        log.message(
            '\n$upgradable upgradable dependencies are locked (in pubspec.lock) '
            'to older versions.\n'
            'To update these dependencies, use `$topLevelProgram pub upgrade`.');
      }
    }

    if (notAtResolvable == 0 &&
        upgradable == 0 &&
        rows.isNotEmpty &&
        (directRows.isNotEmpty || devRows.isNotEmpty)) {
      log.message(
          "You are already using the newest resolvable versions listed in the 'Resolvable' column.\n"
          "Newer versions, listed in 'Latest', may not be mutually compatible.");
    } else if (directRows.isEmpty && devRows.isEmpty) {
      log.message(mode.allSafe);
    }
  } else {
    log.message('\nNo pubspec.lock found. There are no Current versions.\n'
        'Run `$topLevelProgram pub get` to create a pubspec.lock with versions matching your '
        'pubspec.yaml.');
  }
  if (notAtResolvable != 0) {
    if (notAtResolvable == 1) {
      log.message('\n1 dependency is constrained to a '
          'version that is older than a resolvable version.\n'
          'To update it, ${mode.upgradeConstrained}.');
    } else {
      log.message('\n$notAtResolvable  dependencies are constrained to '
          'versions that are older than a resolvable version.\n'
          'To update these dependencies, ${mode.upgradeConstrained}.');
    }
  }
  if (rows.any((package) => package.isDiscontinued)) {
    log.message('\n');
    for (var package in rows.where((package) => package.isDiscontinued)) {
      log.message(log.bold(package.name));
      final replacedByText = package.discontinuedReplacedBy != null
          ? ', replaced by ${package.discontinuedReplacedBy}.'
          : '.';
      log.message(
        '    Package ${package.name} has been discontinued$replacedByText',
      );
    }
  }
}

abstract class _Mode {
  /// Analyzes the [_PackageDetails] according to a --mode and outputs a
  /// corresponding list of the versions
  /// [current, upgradable, resolvable, latest].
  Future<List<List<_MarkedVersionDetails>>> markVersionDetails(
    List<_PackageDetails> packageDetails,
  );

  String explanation(String directoryDescription);
  String get foundNoBadText;
  String get allGood;
  String get noResolutionText;
  String get upgradeConstrained;
  String get allSafe;

  Future<Pubspec> resolvablePubspec(Pubspec pubspec);
}

class _OutdatedMode implements _Mode {
  @override
  String explanation(String directoryDescription) => '''
Showing outdated packages$directoryDescription.
[${log.red('*')}] indicates versions that are not the latest available.
''';

  @override
  String get foundNoBadText => 'Found no outdated packages';

  @override
  String get allGood => 'all up-to-date.';

  @override
  String get noResolutionText =>
      '''No resolution was found. Try running `$topLevelProgram pub upgrade --dry-run` to explore why.''';

  @override
  String get upgradeConstrained =>
      'edit pubspec.yaml, or run `$topLevelProgram pub upgrade --major-versions`';

  @override
  String get allSafe => 'all dependencies are up-to-date.';

  @override
  Future<List<List<_MarkedVersionDetails>>> markVersionDetails(
    List<_PackageDetails> packages,
  ) async {
    final rows = <List<_MarkedVersionDetails>>[];
    for (final packageDetails in packages) {
      final cols = <_MarkedVersionDetails>[];
      _VersionDetails? previous;
      for (final versionDetails in [
        packageDetails.current,
        packageDetails.upgradable,
        packageDetails.resolvable,
        packageDetails.latest
      ]) {
        String Function(String)? color;
        String? prefix;
        String? suffix;
        var asDesired = false;
        if (versionDetails != null) {
          final isLatest = versionDetails == packageDetails.latest;
          if (isLatest) {
            color = versionDetails == previous ? color = log.gray : null;
            asDesired = true;
            if (packageDetails.isDiscontinued &&
                identical(versionDetails, packageDetails.latest)) {
              suffix = ' (discontinued)';
            }
          } else {
            color = log.red;
          }
          prefix = isLatest ? '' : '*';
        }
        cols.add(
          _MarkedVersionDetails(
            versionDetails,
            asDesired: asDesired,
            format: color,
            prefix: prefix,
            suffix: suffix,
          ),
        );
        previous = versionDetails;
      }
      rows.add(cols);
    }
    return rows;
  }

  @override
  Future<Pubspec> resolvablePubspec(Pubspec? pubspec) async {
    return stripVersionBounds(pubspec!);
  }
}

/// Details about a single version of a package.
class _VersionDetails {
  final Pubspec _pubspec;

  /// True if this version is overridden.
  final bool _overridden;
  final PackageId _id;
  _VersionDetails(this._pubspec, this._id, this._overridden);

  /// A string representation of this version to include in the outdated report.
  String get describe {
    final version = _pubspec.version;
    var suffix = '';
    if (_overridden) {
      suffix = ' (overridden)';
    } else if (_id.source is SdkSource) {
      // Version is not relevant for sdk-packages.
      return '(sdk)';
    } else if (_id.source is GitSource) {
      suffix = ' (git)';
    } else if (_id.source is PathSource) {
      suffix = ' (path)';
    }
    return '$version$suffix';
  }

  Map<String, Object> toJson() => {
        'version': _pubspec.version.toString(),
        if (_overridden) 'overridden': true,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _VersionDetails &&
          _overridden == other._overridden &&
          _id.source == other._id.source &&
          _pubspec.version == other._pubspec.version;

  bool operator <(_VersionDetails other) =>
      _overridden == other._overridden &&
      _id.source == other._id.source &&
      _pubspec.version < other._pubspec.version;

  @override
  int get hashCode => Object.hash(_pubspec.version, _id.source, _overridden);
}

class _PackageDetails implements Comparable<_PackageDetails> {
  final String name;
  final _VersionDetails? current;
  final _VersionDetails? upgradable;
  final _VersionDetails? resolvable;
  final _VersionDetails? latest;
  final _DependencyKind kind;
  final bool isDiscontinued;
  final String? discontinuedReplacedBy;

  _PackageDetails(
    this.name,
    this.current,
    this.upgradable,
    this.resolvable,
    this.latest,
    this.kind,
    this.isDiscontinued,
    this.discontinuedReplacedBy,
  );

  @override
  int compareTo(_PackageDetails other) {
    if (kind != other.kind) {
      return kind.index.compareTo(other.kind.index);
    }
    return name.compareTo(other.name);
  }

  Map<String, Object?> toJson() {
    return {
      'package': name,
      'current': current?.toJson(),
      'upgradable': upgradable?.toJson(),
      'resolvable': resolvable?.toJson(),
      'latest': latest?.toJson(),
      'isDiscontinued': isDiscontinued,
      'discontinuedReplacedBy': discontinuedReplacedBy,
    };
  }
}

_DependencyKind _kind(
  String name,
  Entrypoint entrypoint,
  Set<String> nonDevTransitive,
) {
  if (entrypoint.root.dependencies.containsKey(name)) {
    return _DependencyKind.direct;
  } else if (entrypoint.root.devDependencies.containsKey(name)) {
    return _DependencyKind.dev;
  } else {
    if (nonDevTransitive.contains(name)) {
      return _DependencyKind.transitive;
    } else {
      return _DependencyKind.devTransitive;
    }
  }
}

enum _DependencyKind {
  /// Direct non-dev dependencies.
  direct,

  /// Direct dev dependencies.
  dev,

  /// Transitive dependencies of direct dependencies.
  transitive,

  /// Transitive dependencies needed only by dev_dependencies.
  devTransitive,
}

_FormattedString _format(
  String value,
  String Function(String) format, {
  String? prefix = '',
}) {
  return _FormattedString(value, format: format, prefix: prefix);
}

class _MarkedVersionDetails {
  final MapEntry<String, Object>? _jsonExplanation;
  final _VersionDetails? _versionDetails;
  final String Function(String)? _format;
  final String? _prefix;
  final String? _suffix;

  /// This should be true if the mode creating this consideres the version as
  /// "good".
  ///
  /// By default only packages with a current version that is not as desired
  /// will be shown in the report.
  final bool asDesired;

  _MarkedVersionDetails(
    this._versionDetails, {
    required this.asDesired,
    String Function(String)? format,
    String? prefix = '',
    String? suffix = '',
    MapEntry<String, Object>? jsonExplanation,
  })  : _format = format,
        _prefix = prefix,
        _suffix = suffix,
        _jsonExplanation = jsonExplanation;

  _FormattedString toHuman() => _FormattedString(
        _versionDetails?.describe ?? '-',
        format: _format,
        prefix: _prefix,
        suffix: _suffix,
      );

  Object? toJson() {
    if (_versionDetails == null) return null;

    var jsonExplanation = _jsonExplanation;
    return jsonExplanation == null
        ? _versionDetails!.toJson()
        : (_versionDetails!.toJson()..addEntries([jsonExplanation]));
  }
}

class _FormattedString {
  final String value;

  /// Should apply the ansi codes to present this string.
  final String Function(String) _format;

  /// A prefix for marking this string if colors are not used.
  final String _prefix;

  final String _suffix;

  _FormattedString(
    this.value, {
    String Function(String)? format,
    String? prefix,
    String? suffix,
  })  : _format = format ?? _noFormat,
        _prefix = prefix ?? '',
        _suffix = suffix ?? '';

  String formatted({required bool useColors}) {
    return useColors
        ? _format(_prefix + value + _suffix)
        : _prefix + value + _suffix;
  }

  int computeLength({required bool? useColors}) {
    return _prefix.length + value.length + _suffix.length;
  }

  static String _noFormat(String x) => x;
}
