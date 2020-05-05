// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pub_semver/pub_semver.dart';
import 'package:meta/meta.dart';

import '../command.dart';
import '../entrypoint.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../solver.dart';
import '../source/hosted.dart';
import '../utils.dart';

class OutdatedCommand extends PubCommand {
  @override
  String get name => 'outdated';
  @override
  String get description =>
      'Analyze your dependencies to find which ones can be upgraded.';
  @override
  String get invocation => 'pub outdated [options]';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-outdated';

  OutdatedCommand() {
    argParser.addFlag('color',
        help: 'Whether to color the output.\n'
            'Defaults to color when connected to a '
            'terminal, and no-color otherwise.');

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

    argParser.addFlag('json',
        help: 'Output the results using a json format.', negatable: false);

    argParser.addOption('mark',
        help: 'Highlight packages with some property in the report.',
        valueHelp: 'OPTION',
        allowed: ['outdated', 'none'],
        defaultsTo: 'outdated',
        hide: true);

    argParser.addFlag('prereleases',
        defaultsTo: false, help: 'Include prereleases in latest version.');

    // Preserve for backwards compatibility.
    argParser.addFlag('pre-releases',
        defaultsTo: false, help: 'Alias of prereleases.', hide: true);

    argParser.addFlag('up-to-date',
        defaultsTo: false,
        help: 'Include dependencies that are already at the '
            'latest version.');
  }

  @override
  Future run() async {
    entrypoint.assertUpToDate();

    final includeDevDependencies = argResults['dev-dependencies'];
    final includeDependencyOverrides = argResults['dependency-overrides'];

    final rootPubspec = includeDependencyOverrides
        ? entrypoint.root.pubspec
        : _stripDependencyOverrides(entrypoint.root.pubspec);

    final upgradablePubspec = includeDevDependencies
        ? rootPubspec
        : _stripDevDependencies(rootPubspec);

    final resolvablePubspec = _stripVersionConstraints(upgradablePubspec);

    List<PackageId> upgradablePackages;
    List<PackageId> resolvablePackages;

    final shouldShowSpinner = stdout.hasTerminal && !argResults['json'];
    if (shouldShowSpinner) {
      await log.spinner('Resolving', () async {
        upgradablePackages = await _tryResolve(upgradablePubspec);
        resolvablePackages = await _tryResolve(resolvablePubspec);
      });
    } else {
      upgradablePackages = await _tryResolve(upgradablePubspec);
      resolvablePackages = await _tryResolve(resolvablePubspec);
    }

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
      final current = (entrypoint.lockFile?.packages ?? {})[name];

      final upgradable = upgradablePackages.firstWhere((id) => id.name == name,
          orElse: () => null);
      final resolvable = resolvablePackages.firstWhere((id) => id.name == name,
          orElse: () => null);

      // Find the latest version, and if it's overridden.
      var latestIsOverridden = false;
      PackageId latest;
      // If not overridden in current resolution we can use this
      if (!entrypoint.root.pubspec.dependencyOverrides.containsKey(name)) {
        latest ??= await _getLatest(current);
      }
      // If present as a dependency or dev_dependency we use this
      latest ??= await _getLatest(rootPubspec.dependencies[name]);
      latest ??= await _getLatest(rootPubspec.devDependencies[name]);
      // If not overridden and present in either upgradable or resolvable we
      // use this reference to find the latest
      if (!upgradablePubspec.dependencyOverrides.containsKey(name)) {
        latest ??= await _getLatest(upgradable);
      }
      if (!resolvablePubspec.dependencyOverrides.containsKey(name)) {
        latest ??= await _getLatest(resolvable);
      }
      // Otherwise, we might simply not have a latest, when a transitive
      // dependency is overridden the source can depend on which versions we
      // are picking. This is not a problem on `pub.dev` because it does not
      // allow 3rd party pub servers, but other servers might. Hence, we choose
      // to fallback to using the overridden source for latest.
      if (latest == null) {
        latest ??= await _getLatest(current ?? upgradable ?? resolvable);
        latestIsOverridden = true;
      }

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

    if (!argResults['up-to-date']) {
      rows.retainWhere((r) => (r.current ?? r.upgradable) != r.latest);
    }
    if (!includeDevDependencies) {
      rows.removeWhere((r) => r.kind == _DependencyKind.dev);
    }

    rows.sort();

    if (argResults['json']) {
      await _outputJson(rows);
    } else {
      if (argResults.wasParsed('color') && argResults['color']) {
        forceColors = true;
      }
      final useColors = argResults['color'] || canUseSpecialChars;
      final marker = {
        'outdated': oudatedMarker,
        'none': noneMarker,
      }[argResults['mark']];
      await _outputHuman(
        rows,
        marker,
        useColors: useColors,
        includeDevDependencies: includeDevDependencies,
      );
    }
  }

  /// Get the latest version of [package].
  ///
  /// Returns `null`, if unable to find the package.
  Future<PackageId> _getLatest(PackageName package) async {
    if (package == null) {
      return null;
    }
    final ref = package.toRef();
    final available = await cache.source(ref.source).getVersions(ref);
    if (available.isEmpty) {
      return null;
    }
    final prereleases = argResults.wasParsed('prereleases')
        ? argResults['prereleases']
        : argResults['pre-releases'];
    available.sort(prereleases
        ? (x, y) => x.version.compareTo(y.version)
        : (x, y) => Version.prioritize(x.version, y.version));
    return available.last;
  }

  /// Retrieves the pubspec of package [name] in [version] from [source].
  ///
  /// Returns `null`, if given `null` as a convinience.
  Future<_VersionDetails> _describeVersion(
    PackageId id,
    bool isOverridden,
  ) async {
    if (id == null) {
      return null;
    }
    return _VersionDetails(
      await cache.source(id.source).describe(id),
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
      key: (id) => id.name,
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
      final pubspec = await cache.source(id.source).describe(id);
      queue.addAll(pubspec.dependencies.keys);
    }

    return nonDevDependencies;
  }

  /// Try to solve [pubspec] return [PackageId]'s in the resolution or `null`.
  Future<List<PackageId>> _tryResolve(Pubspec pubspec) async {
    try {
      return (await resolveVersions(
        SolveType.UPGRADE,
        cache,
        Package.inMemory(pubspec),
      ))
          .packages;
    } on SolveFailure {
      return [];
    }
  }
}

Pubspec _stripDevDependencies(Pubspec original) {
  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: original.dependencies.values,
    devDependencies: [], // explicitly give empty list, to prevent lazy parsing
    dependencyOverrides: original.dependencyOverrides.values,
  );
}

Pubspec _stripDependencyOverrides(Pubspec original) {
  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: original.dependencies.values,
    devDependencies: original.devDependencies.values,
    dependencyOverrides: [],
  );
}

/// Returns new pubspec with the same dependencies as [original] but with no
/// version constraints on hosted packages.
Pubspec _stripVersionConstraints(Pubspec original) {
  List<PackageRange> _unconstrained(Map<String, PackageRange> constrained) {
    final result = <PackageRange>[];
    for (final name in constrained.keys) {
      final packageRange = constrained[name];
      var unconstrainedRange = packageRange;
      if (packageRange.source is HostedSource) {
        unconstrainedRange = PackageRange(
            packageRange.name,
            packageRange.source,
            VersionConstraint.any,
            packageRange.description,
            features: packageRange.features);
      }
      result.add(unconstrainedRange);
    }
    return result;
  }

  return Pubspec(
    original.name,
    version: original.version,
    sdkConstraints: original.sdkConstraints,
    dependencies: _unconstrained(original.dependencies),
    devDependencies: _unconstrained(original.devDependencies),
    dependencyOverrides: original.dependencyOverrides.values,
  );
}

Future<void> _outputJson(List<_PackageDetails> rows) async {
  log.message(JsonEncoder.withIndent('  ')
      .convert({'packages': rows.map((row) => row.toJson()).toList()}));
}

Future<void> _outputHuman(
  List<_PackageDetails> rows,
  Future<List<_FormattedString>> Function(_PackageDetails) marker, {
  @required bool useColors,
  @required bool includeDevDependencies,
}) async {
  if (rows.isEmpty) {
    log.message('Found no outdated packages.');
    return;
  }
  final directRows = rows.where((row) => row.kind == _DependencyKind.direct);
  final devRows = rows.where((row) => row.kind == _DependencyKind.dev);
  final transitiveRows =
      rows.where((row) => row.kind == _DependencyKind.transitive);
  final devTransitiveRows =
      rows.where((row) => row.kind == _DependencyKind.devTransitive);

  final formattedRows = <List<_FormattedString>>[
    ['Dependencies', 'Current', 'Upgradable', 'Resolvable', 'Latest']
        .map((s) => _format(s, log.bold))
        .toList(),
    [if (directRows.isEmpty) _raw('all up-to-date')],
    ...await Future.wait(directRows.map(marker)),
    if (includeDevDependencies) ...[
      [
        devRows.isEmpty
            ? _raw('\ndev_dependencies: all up-to-date')
            : _format('\ndev_dependencies', log.bold),
      ],
      ...await Future.wait(devRows.map(marker)),
    ],
    [
      transitiveRows.isEmpty
          ? _raw('\ntransitive dependencies: all up-to-date')
          : _format('\ntransitive dependencies', log.bold)
    ],
    ...await Future.wait(transitiveRows.map(marker)),
    if (includeDevDependencies) ...[
      [
        devTransitiveRows.isEmpty
            ? _raw('\ntransitive dev_dependencies: all up-to-date')
            : _format('\ntransitive dev_dependencies', log.bold)
      ],
      ...await Future.wait(devTransitiveRows.map(marker)),
    ],
  ];

  final columnWidths = <int, int>{};
  for (var i = 0; i < formattedRows.length; i++) {
    if (formattedRows[i].length > 1) {
      for (var j = 0; j < formattedRows[i].length; j++) {
        final currentMaxWidth = columnWidths[j] ?? 0;
        columnWidths[j] = max(
            formattedRows[i][j].computeLength(useColors: useColors),
            currentMaxWidth);
      }
    }
  }

  for (final row in formattedRows) {
    final b = StringBuffer();
    for (var j = 0; j < row.length; j++) {
      b.write(row[j].formatted(useColors: useColors));
      b.write(' ' *
          ((columnWidths[j] + 2) - row[j].computeLength(useColors: useColors)));
    }
    log.message(b.toString());
  }

  var upgradable = rows
      .where((row) =>
          row.current != null &&
          row.upgradable != null &&
          row.current != row.upgradable)
      .length;

  var notAtResolvable = rows
      .where((row) =>
          row.current != null &&
          row.resolvable != null &&
          row.upgradable != row.resolvable)
      .length;

  if (upgradable != 0) {
    if (upgradable == 1) {
      log.message('\n1 upgradable dependency is locked (in pubspec.lock) to '
          'an older version.\n'
          'To update it, use `pub upgrade`.');
    } else {
      log.message(
          '\n$upgradable upgradable dependencies are locked (in pubspec.lock) '
          'to older versions.\n'
          'To update these dependencies, use `pub upgrade`.');
    }
  }

  if (notAtResolvable != 0) {
    if (notAtResolvable == 1) {
      log.message('\n1 dependency is constrained to a '
          'version that is older than a resolvable version.\n'
          'To update it, edit pubspec.yaml.');
    } else {
      log.message('\n$notAtResolvable  dependencies are constrained to '
          'versions that are older than a resolvable version.\n'
          'To update these dependencies, edit pubspec.yaml.');
    }
  }

  if (notAtResolvable == 0 && upgradable == 0 && rows.isNotEmpty) {
    log.message('\nDependencies are all on the latest resolvable versions.'
        '\nNewer versions, while available, are not mutually compatible.');
  }
}

Future<List<_FormattedString>> oudatedMarker(
    _PackageDetails packageDetails) async {
  final cols = [_FormattedString(packageDetails.name)];
  _VersionDetails previous;
  for (final versionDetails in [
    packageDetails.current,
    packageDetails.upgradable,
    packageDetails.resolvable,
    packageDetails.latest
  ]) {
    if (versionDetails == null) {
      cols.add(_raw('-'));
    } else {
      final isLatest = versionDetails == packageDetails.latest;
      String Function(String) color;
      if (isLatest) {
        color = versionDetails == previous ? color = log.gray : null;
      } else {
        color = log.red;
      }
      final prefix = isLatest ? '' : '*';
      cols.add(_format(versionDetails.describe ?? '-', color, prefix: prefix));
    }
    previous = versionDetails;
  }
  return cols;
}

Future<List<_FormattedString>> noneMarker(
    _PackageDetails packageDetails) async {
  return [
    _FormattedString(packageDetails.name),
    ...[
      packageDetails.current,
      packageDetails.upgradable,
      packageDetails.resolvable,
      packageDetails.latest,
    ].map((p) => _raw(p?.describe ?? '-'))
  ];
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
    final suffix = _overridden ? ' (overridden)' : '';
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
}

class _PackageDetails implements Comparable<_PackageDetails> {
  final String name;
  final _VersionDetails current;
  final _VersionDetails upgradable;
  final _VersionDetails resolvable;
  final _VersionDetails latest;
  final _DependencyKind kind;

  _PackageDetails(this.name, this.current, this.upgradable, this.resolvable,
      this.latest, this.kind);

  @override
  int compareTo(_PackageDetails other) {
    if (kind != other.kind) {
      return kind.index.compareTo(other.kind.index);
    }
    return name.compareTo(other.name);
  }

  Map<String, Object> toJson() {
    return {
      'package': name,
      'current': current?.toJson(),
      'upgradable': upgradable?.toJson(),
      'resolvable': resolvable?.toJson(),
      'latest': latest?.toJson(),
    };
  }
}

_DependencyKind _kind(
    String name, Entrypoint entrypoint, Set<String> nonDevTransitive) {
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

_FormattedString _format(String value, Function(String) format, {prefix = ''}) {
  return _FormattedString(value, format: format, prefix: prefix);
}

_FormattedString _raw(String value) => _FormattedString(value);

class _FormattedString {
  final String value;

  /// Should apply the ansi codes to present this string.
  final String Function(String) _format;

  /// A prefix for marking this string if colors are not used.
  final String _prefix;

  _FormattedString(this.value, {String Function(String) format, prefix = ''})
      : _format = format ?? _noFormat,
        _prefix = prefix;

  String formatted({@required bool useColors}) {
    return useColors ? _format(value) : _prefix + value;
  }

  int computeLength({@required bool useColors}) {
    return useColors ? value.length : _prefix.length + value.length;
  }

  static String _noFormat(String x) => x;
}
