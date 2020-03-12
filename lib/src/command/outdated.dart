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
import '../source.dart';
import '../source/hosted.dart';

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
    argParser.addOption('format',
        help: 'Defines how the output should be formatted. Defaults to color '
            'when connected to a terminal, and no-color otherwise.',
        valueHelp: 'FORMAT',
        allowed: ['color', 'no-color', 'json']);

    argParser.addFlag('up-to-date',
        defaultsTo: false,
        help: 'Include dependencies that are already at the latest version');

    argParser.addFlag('pre-releases',
        defaultsTo: false,
        help: 'Include pre-releases when reporting latest version');

    argParser.addFlag(
      'dev-dependencies',
      defaultsTo: true,
      help: 'When true take dev-dependencies into account when resolving.',
    );

    argParser.addOption('mark',
        help: 'Highlight packages with some property in the report.',
        valueHelp: 'OPTION',
        allowed: ['outdated', 'none'],
        defaultsTo: 'outdated');
  }

  @override
  Future run() async {
    entrypoint.assertUpToDate();

    final includeDevDependencies = argResults['dev-dependencies'];

    final upgradePubspec = includeDevDependencies
        ? entrypoint.root.pubspec
        : _stripDevDependencies(entrypoint.root.pubspec);

    var resolvablePubspec = _stripVersionConstraints(upgradePubspec);

    SolveResult upgradableSolveResult;
    SolveResult resolvableSolveResult;

    await log.warningsOnlyUnlessTerminal(
      () => log.spinner(
        'Resolving',
        () async {
          upgradableSolveResult = await resolveVersions(
            SolveType.UPGRADE,
            cache,
            Package.inMemory(upgradePubspec),
          );

          resolvableSolveResult = await resolveVersions(
            SolveType.UPGRADE,
            cache,
            Package.inMemory(resolvablePubspec),
          );
        },
      ),
    );

    Future<_PackageDetails> analyzeDependency(PackageRef packageRef) async {
      final name = packageRef.name;
      final current = (entrypoint.lockFile?.packages ?? {})[name]?.version;
      final source = packageRef.source;
      final available = (await cache.source(source).doGetVersions(packageRef))
          .map((id) => id.version)
          .toList()
            ..sort(argResults['pre-releases'] ? null : Version.prioritize);
      final upgradable = upgradableSolveResult.packages
          .firstWhere((id) => id.name == name, orElse: () => null)
          ?.version;
      final resolvable = resolvableSolveResult.packages
          .firstWhere((id) => id.name == name, orElse: () => null)
          ?.version;
      final latest = available.last;
      final description = packageRef.description;
      return _PackageDetails(
          name,
          await _describeVersion(name, source, description, current),
          await _describeVersion(name, source, description, upgradable),
          await _describeVersion(name, source, description, resolvable),
          await _describeVersion(name, source, description, latest),
          _kind(name, entrypoint));
    }

    final rows = <_PackageDetails>[];

    final immediateDependencies = entrypoint.root.immediateDependencies.values;

    for (final packageRange in immediateDependencies) {
      rows.add(await analyzeDependency(packageRange.toRef()));
    }

    // Now add transitive dependencies:
    final visited = <String>{
      entrypoint.root.name,
      ...immediateDependencies.map((d) => d.name)
    };
    for (final id in [
      if (includeDevDependencies) ...entrypoint.lockFile.packages.values,
      ...upgradableSolveResult.packages,
      ...resolvableSolveResult.packages
    ]) {
      final name = id.name;
      if (!visited.add(name)) continue;
      rows.add(await analyzeDependency(id.toRef()));
    }

    if (!argResults['up-to-date']) {
      rows.retainWhere(
          (r) => (r.current ?? r.upgradable)?.version != r.latest?.version);
    }
    if (!includeDevDependencies) {
      rows.removeWhere((r) => r.kind == _DependencyKind.dev);
    }

    rows.sort();

    if (argResults['format'] == 'json') {
      await _outputJson(rows);
    } else {
      final useColors = argResults['format'] == 'color' ||
          (!argResults.wasParsed('format') && stdin.hasTerminal);
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

  /// Retrieves the pubspec of package [name] in [version] from [source].
  Future<Pubspec> _describeVersion(
      String name, Source source, dynamic description, Version version) async {
    return version == null
        ? null
        : await cache
            .source(source)
            .describe(PackageId(name, source, version, description));
  }
}

Pubspec _stripDevDependencies(Pubspec original) {
  return Pubspec(
    original.name,
    sdkConstraints: original.sdkConstraints,
    dependencies: original.dependencies.values,
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
    sdkConstraints: original.sdkConstraints,
    dependencies: _unconstrained(original.dependencies),
    devDependencies: _unconstrained(original.devDependencies),
    // TODO(sigurdm): consider dependency overrides.
  );
}

Future<void> _outputJson(List<_PackageDetails> rows) async {
  log.message(JsonEncoder.withIndent('  ')
      .convert({'packages': rows.map((row) => row.toJson()).toList()}));
}

Future<void> _outputHuman(List<_PackageDetails> rows,
    Future<List<_FormattedString>> Function(_PackageDetails) marker,
    {@required bool useColors, @required bool includeDevDependencies}) async {
  if (rows.isEmpty) {
    log.message('Found no outdated packages');
    return;
  }
  final directRows = rows.where((row) => row.kind == _DependencyKind.direct);
  final devRows = rows.where((row) => row.kind == _DependencyKind.dev);
  final transitiveRows =
      rows.where((row) => row.kind == _DependencyKind.transitive);

  final formattedRows = <List<_FormattedString>>[
    ['Package', 'Current', 'Upgradable', 'Resolvable', 'Latest']
        .map((s) => _format(s, log.bold))
        .toList(),
    [
      directRows.isEmpty
          ? _raw('dependencies: all up-to-date')
          : _format('dependencies', log.bold),
    ],
    ...await Future.wait(directRows.map(marker)),
    if (includeDevDependencies)
      [
        devRows.isEmpty
            ? _raw('\ndev_dependencies: all up-to-date')
            : _format('\ndev_dependencies', log.bold),
      ],
    ...await Future.wait(devRows.map(marker)),
    [
      transitiveRows.isEmpty
          ? _raw('\ntransitive dependencies: all up-to-date')
          : _format('\ntransitive dependencies', log.bold)
    ],
    ...await Future.wait(transitiveRows.map(marker)),
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
      .where(
          (row) => row.resolvable != null && row.upgradable != row.resolvable)
      .length;

  if (upgradable != 0) {
    if (upgradable == 1) {
      log.message('1 upgradable dependency is locked (in pubspec.lock) to '
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
}

Future<List<_FormattedString>> oudatedMarker(
    _PackageDetails packageDetails) async {
  final cols = [_FormattedString(packageDetails.name)];
  Version previous;
  for (final pubspec in [
    packageDetails.current,
    packageDetails.upgradable,
    packageDetails.resolvable,
    packageDetails.latest
  ]) {
    final version = pubspec?.version;
    if (version == null) {
      cols.add(_raw('-'));
    } else {
      final isLatest = version == packageDetails.latest.version;
      String Function(String) color;
      if (isLatest) {
        color = version == previous ? color = log.gray : null;
      } else {
        color = log.red;
      }
      final prefix = isLatest ? '' : '*';
      cols.add(_format(version?.toString() ?? '-', color, prefix: prefix));
    }
    previous = version;
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
    ].map((p) => _raw(p?.version?.toString() ?? '-'))
  ];
}

class _PackageDetails implements Comparable<_PackageDetails> {
  final String name;
  final Pubspec current;
  final Pubspec upgradable;
  final Pubspec resolvable;
  final Pubspec latest;
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
      'current': current?.version?.toString(),
      'upgradable': upgradable?.version?.toString(),
      'resolvable': resolvable?.version?.toString(),
      'latest': latest?.version?.toString(),
    };
  }
}

_DependencyKind _kind(String name, Entrypoint entrypoint) {
  if (entrypoint.root.dependencies.containsKey(name)) {
    return _DependencyKind.direct;
  } else if (entrypoint.root.devDependencies.containsKey(name)) {
    return _DependencyKind.dev;
  } else {
    return _DependencyKind.transitive;
  }
}

enum _DependencyKind {
  /// Direct non-dev dependencies.
  direct,

  /// Direct dev dependencies.
  dev,

  /// Transitive dependencies.
  transitive
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
