// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:meta/meta.dart';

import '../command.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../solver.dart';
import '../source.dart';

/// Handles the `upgrade` pub command.
class OutdatedCommand extends PubCommand {
  @override
  String get name => 'outdated';
  @override
  String get description =>
      'Analyze your dependencies to find which ones can be upgraded.';
  @override
  String get invocation => 'pub outdated [options]';
  @override
  String get docUrl =>
      'https://dart.dev/tools/pub/cmd/pub-outdated'; // TODO(sigurdm): create this

  OutdatedCommand() {
    argParser.addOption('format',
        help:
            'Defines how the output should be formatted. Defaults to color when'
            'connected to a terminal, and no-color otherwise.',
        valueHelp: 'TYPE',
        allowed: ['color', 'no-color', 'json']);

    argParser.addMultiOption('include',
        allowed: ['pre-releases', 'transitive', 'up-to-date'],
        help:
            'pre-releases: include pre-releases when reporting latest version.\n'
            'up-to-date: include dependencies that are already at the latest version.\n'
            'transitive: include transitive dependencies in the reports',
        valueHelp: 'optionA,optionB');

    argParser.addMultiOption('exclude',
        allowed: ['dev-dependencies'],
        help:
            'dev-dependencies: do not take dev-dependencies into account when resolving.',
        valueHelp: 'options');

    argParser.addOption('mark',
        help: 'Highlight packages with some property in the report.',
        valueHelp: 'OPTION',
        allowed: ['outdated', 'none'],
        defaultsTo: 'outdated');
  }

  @override
  Future run() async {
    final includeDevDependencies =
        !argResults['exclude'].contains('dev-dependencies');

    final oldVerbosity = log.verbosity;
    // Unless the user overrides the verbosity, we want to filter out the
    // normal pub output from 'Resolving dependencies...` if we are
    // not attached to a terminal. This is to not pollute stdout when the output
    // of `pub run` is piped somewhere.
    if (log.verbosity == log.Verbosity.NORMAL && !stdout.hasTerminal) {
      log.verbosity = log.Verbosity.WARNING;
    }

    final unconstrained = Package.inMemory(_loosenConstraints(
        entrypoint.root.pubspec,
        includeDevDependencies: includeDevDependencies));

    final solveResult = await resolveVersions(
      SolveType.UPGRADE,
      cache,
      unconstrained,
    );

    log.verbosity = oldVerbosity;

    Future<_PackageDetails> analyzeDependency(PackageRange packageRange) async {
      final name = packageRange.name;
      final current = (entrypoint.lockFile?.packages ?? {})[name]?.version;
      final source = packageRange.source;
      final available = (await cache
              .source(source)
              .doGetVersions(packageRange.toRef()))
          .map((id) => id.version)
          .toList()
            ..sort(argResults['include'].contains('pre-releases')
                ? null
                : Version.prioritize);
      final constraint = packageRange.constraint;
      final allowed = constraint == null
          ? null
          : available.lastWhere(constraint.allows, orElse: () => null);
      final resolvable = solveResult.packages
          .firstWhere((id) => id.name == name, orElse: () => null)
          ?.version;
      final latest = available.last;
      final description = packageRange.description;
      return _PackageDetails(
          name,
          await _describeVersion(name, source, description, current),
          await _describeVersion(name, source, description, allowed),
          await _describeVersion(name, source, description, resolvable),
          await _describeVersion(name, source, description, latest),
          _kind(name, entrypoint));
    }

    final rows = <_PackageDetails>[];

    final immediateDependencies = entrypoint.root.immediateDependencies.values;

    for (final packageRange in immediateDependencies) {
      rows.add(await analyzeDependency(packageRange));
    }

    if (argResults['include'].contains('transitive')) {
      final visited = <String>{};
      for (final id in [
        if (includeDevDependencies) ...entrypoint.lockFile.packages.values,
        ...solveResult.packages
      ]) {
        final name = id.name;
        if (visited.contains(name) ||
            name == entrypoint.root.name ||
            immediateDependencies.any((r) => r.name == name)) continue;
        visited.add(name);
        rows.add(await analyzeDependency(PackageRange(
            name,
            id.source,
            // No allowed version for transitive dependencies.
            VersionConstraint.empty,
            id.description)));
      }
    }

    if (!argResults['include'].contains('up-to-date')) {
      rows.retainWhere(
          (r) => (r.current ?? r.allowed)?.version != r.latest?.version);
    }
    if (argResults['exclude'].contains('dev-dependencies')) {
      rows.removeWhere((r) => r.kind == _DependencyKind.dev);
    }

    rows.sort();

    if (argResults['format'] == 'json') {
      // TODO(sigurdm): decide on and document the json format.
      await _outputJson(rows);
    } else {
      final useColors = argResults['format'] == 'color' ||
          (!argResults.wasParsed('format') && stdin.hasTerminal);
      final marker = {
        'outdated': _OutdatedMarker(),
        'none': _NoneMarker(),
      }[argResults['mark']];
      await _outputHuman(rows, marker, useColors);
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

/// Returns new pubspec with the same dependencies as [original] but with no
/// version constraints on hosted packages.
Pubspec _loosenConstraints(Pubspec original, {bool includeDevDependencies}) {
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
    dependencies: _unconstrained(original.dependencies),
    devDependencies: includeDevDependencies
        ? _unconstrained(original.devDependencies)
        : null,
    // TODO(sigurdm): consider dependency overrides.
  );
}

Future<void> _outputJson(List<_PackageDetails> rows) async {
  log.message(JsonEncoder.withIndent('  ')
      .convert({'packages': rows.map((row) => row.toJson()).toList()}));
}

Future<void> _outputHuman(
    List<_PackageDetails> rows, _Marker marker, bool useColors) async {
  if (rows.isEmpty) {
    log.message('Found no outdated packages');
    return;
  }
  final formattedRows = <FormattedRow>[
    FormattedRow(
        null,
        ['Package', 'Current', 'Allowed', 'Resolvable', 'Latest']
            .map((s) =>
                _FormattedString(s, formatting: _Formatting(isBold: true)))
            .toList()),
  ];
  for (final row in rows) {
    formattedRows.add(await marker.formatRow(row));
  }
  final columnWidths = <int, int>{};
  for (var i = 0; i < formattedRows.length; i++) {
    for (var j = 0; j < formattedRows[i].columns.length; j++) {
      final currentMaxWidth = columnWidths[j] ?? 0;
      columnWidths[j] = max(
          formattedRows[i].columns[j].computeLength(useColors: useColors),
          currentMaxWidth);
    }
  }
  final outputRows = <String>[];
  _DependencyKind lastKind;
  for (final row in formattedRows) {
    if (lastKind != row.kind) {
      switch (row.kind) {
        case _DependencyKind.production:
          break;
        case _DependencyKind.dev:
          outputRows.add(_FormattedString('\ndev_dependencies',
                  formatting: _Formatting(isBold: true))
              .formatted(useColors: useColors));
          break;
        case _DependencyKind.transitive:
          outputRows.add(_FormattedString('\nTransitive dependencies',
                  formatting: _Formatting(isBold: true))
              .formatted(useColors: useColors));
      }
      lastKind = row.kind;
    }
    final b = StringBuffer();
    for (var j = 0; j < row.columns.length; j++) {
      b.write(row.columns[j].formatted(useColors: useColors));
      b.write(' ' *
          ((columnWidths[j] + 2) -
              row.columns[j].computeLength(useColors: useColors)));
    }
    outputRows.add(b.toString());
  }
  outputRows.forEach(log.message);
}

class FormattedRow {
  final _PackageDetails row;
  final List<_FormattedString> columns;
  FormattedRow(this.row, this.columns);
  _DependencyKind get kind => row?.kind;
}

abstract class _Marker {
  Future<FormattedRow> formatRow(_PackageDetails packageDetails);
}

class _OutdatedMarker implements _Marker {
  _OutdatedMarker();

  @override
  Future<FormattedRow> formatRow(_PackageDetails packageDetails) async {
    final cols = [_FormattedString(packageDetails.name)];
    Version previous;
    for (final pubspec in [
      packageDetails.current,
      packageDetails.allowed,
      packageDetails.resolvable,
      packageDetails.latest
    ]) {
      final version = pubspec?.version;
      final isLatest = version == packageDetails.latest.version;
      final color =
          isLatest ? (version == previous ? Color.gray : null) : Color.red;
      final prefix = isLatest ? '' : '!';
      cols.add(_FormattedString((version ?? '-').toString(),
          formatting: _Formatting(color: color, prefix: prefix)));
      previous = version;
    }
    return FormattedRow(packageDetails, cols);
  }
}

class _NoneMarker implements _Marker {
  @override
  Future<FormattedRow> formatRow(_PackageDetails packageDetails) async {
    return FormattedRow(packageDetails, [
      _FormattedString(packageDetails.name),
      ...[
        packageDetails.current,
        packageDetails.allowed,
        packageDetails.resolvable,
        packageDetails.latest,
      ].map((p) => _FormattedString(p?.version?.toString() ?? '-'))
    ]);
  }
}

class _PackageDetails implements Comparable<_PackageDetails> {
  final String name;
  final Pubspec current;
  final Pubspec allowed;
  final Pubspec resolvable;
  final Pubspec latest;
  final _DependencyKind kind;

  _PackageDetails(this.name, this.current, this.allowed, this.resolvable,
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
      'allowed': allowed?.version?.toString(),
      'resolvable': resolvable?.version?.toString(),
      'latest': latest?.version?.toString(),
    };
  }
}

_DependencyKind _kind(String name, Entrypoint entrypoint) {
  if (entrypoint.root.dependencies.containsKey(name)) {
    return _DependencyKind.production;
  } else if (entrypoint.root.devDependencies.containsKey(name)) {
    return _DependencyKind.dev;
  } else {
    return _DependencyKind.transitive;
  }
}

enum _DependencyKind { production, dev, transitive }

enum Color {
  gray,
  cyan,
  green,
  magenta,
  red,
  yellow,
}

class _Formatting {
  final bool isBold;
  final Color color;
  final String prefix;
  const _Formatting({this.isBold = false, this.color, this.prefix = ''});
  String format(String text, bool useColors) {
    if (useColors) {
      if (isBold) {
        text = log.bold(text);
      }
      if (color != null) {
        switch (color) {
          case Color.gray:
            text = log.gray(text);
            break;
          case Color.cyan:
            text = log.cyan(text);
            break;
          case Color.green:
            text = log.green(text);
            break;
          case Color.magenta:
            text = log.magenta(text);
            break;
          case Color.red:
            text = log.red(text);
            break;
          case Color.yellow:
            text = log.yellow(text);
            break;
        }
      }
      return text;
    }
    return prefix + text;
  }

  int computeLength(String text, {@required bool useColors}) {
    return useColors ? text.length : prefix.length + text.length;
  }
}

class _FormattedString {
  final String value;
  final _Formatting formatting;
  _FormattedString(this.value,
      {this.formatting = const _Formatting(isBold: false)});

  int computeLength({@required bool useColors}) =>
      formatting.computeLength(value, useColors: useColors);
  String formatted({@required bool useColors}) =>
      formatting.format(value, useColors);
}
