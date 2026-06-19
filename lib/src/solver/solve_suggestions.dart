import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:pub_semver/pub_semver.dart';

import '../command_runner.dart';
import '../entrypoint.dart';
import '../flutter_releases.dart';
import '../io.dart';
import '../package.dart';
import '../package_name.dart';
import '../path.dart';
import '../pubspec_utils.dart';
import '../solver.dart';
import '../source.dart';
import '../source/hosted.dart';
import '../source/root.dart';
import '../system_cache.dart';
import 'incompatibility.dart';
import 'incompatibility_cause.dart';

/// Looks through the root-[incompatibility] of a solve-failure and tries to see
/// if the conflict could resolved by any of the following suggestions:
/// * An update of the current SDK.
/// * Any single change to a package constraint.
/// * Removing the bounds on all constraints, changing less than 5 dependencies.
/// * Running `pub upgrade --major versions`.
///
/// Returns a formatted list of suggestions, or the empty String if no
/// suggestions were found.
Future<String?> suggestResolutionAlternatives(
  Entrypoint entrypoint,
  SolveType type,
  Incompatibility incompatibility,
  Iterable<String> unlock,
  SystemCache cache,
) async {
  final resolutionContext = _ResolutionContext(
    entrypoint: entrypoint,
    type: type,
    cache: cache,
    unlock: unlock,
  );

  final visited = <String>{};
  final stopwatch = Stopwatch()..start();
  final suggestions = <_ResolutionSuggestion>[];
  void addSuggestionIfPresent(_ResolutionSuggestion? suggestion) {
    if (suggestion != null) suggestions.add(suggestion);
  }

  for (final externalIncompatibility
      in incompatibility.externalIncompatibilities) {
    if (stopwatch.elapsed > const Duration(seconds: 3)) {
      // Never spend more than 3 seconds computing suggestions.
      break;
    }
    final cause = externalIncompatibility.cause;
    if (cause is SdkIncompatibilityCause) {
      addSuggestionIfPresent(await resolutionContext.suggestSdkUpdate(cause));
    } else {
      for (final term in externalIncompatibility.terms) {
        final name = term.package.name;

        if (!visited.add(name)) {
          continue;
        }
        addSuggestionIfPresent(
          await resolutionContext.suggestSinglePackageUpdate(name),
        );
      }
    }
  }
  if (suggestions.isEmpty) {
    addSuggestionIfPresent(
      await resolutionContext.suggestUnlockingAll(stripLowerBound: true) ??
          await resolutionContext.suggestUnlockingAll(stripLowerBound: false),
    );
  }

  if (suggestions.isEmpty) return null;
  final tryOne =
      suggestions.length == 1
          ? 'You can try the following suggestion to make the pubspec resolve:'
          : 'You can try one of the following suggestions '
              'to make the pubspec resolve:';

  suggestions.sort((a, b) => a.priority.compareTo(b.priority));

  return '\n$tryOne\n'
      '${suggestions.take(5).map((e) => e.suggestion).join('\n')}';
}

class _ResolutionSuggestion {
  final String suggestion;
  final int priority;
  _ResolutionSuggestion(this.suggestion, {this.priority = 0});
}

String? packageAddDescription(
  Package package,
  PackageId id, {
  PackageRange? originalRange,
  required bool isDev,
}) {
  final name = id.name;
  final resolvedDescription = id.description.description;

  final Description? descriptionToSerialize;
  if (resolvedDescription is RootDescription) {
    final originalDescription = originalRange?.description;
    if (originalDescription == null || originalDescription is RootDescription) {
      descriptionToSerialize = null;
    } else if (originalDescription is! HostedDescription) {
      return null;
    } else {
      descriptionToSerialize = originalDescription;
    }
  } else {
    descriptionToSerialize = resolvedDescription;
  }

  final String descriptor;
  if (descriptionToSerialize == null) {
    descriptor = VersionConstraint.compatibleWith(id.version).toString();
  } else {
    final d = descriptionToSerialize.serializeForPubspec(
      containingDir: Directory.current.path,
      languageVersion: package.pubspec.languageVersion,
    );
    if (d == null) {
      descriptor = VersionConstraint.compatibleWith(id.version).toString();
    } else {
      descriptor = json.encode({
        'version': VersionConstraint.compatibleWith(id.version).toString(),
        descriptionToSerialize.source.name: d,
      });
    }
  }

  final devPart = isDev ? 'dev:' : '';
  return '$devPart$name:${escapeShellArgument(descriptor)}';
}

String _packageAddCommand(
  Entrypoint entrypoint,
  Package package,
  Iterable<String> addDescriptions,
) {
  final command = StringBuffer('$topLevelProgram pub add');
  if (_needsDirectoryOption(package)) {
    final packageDir = escapeShellArgument(
      p.normalize(p.relative(package.dir)),
    );
    command.write(' --directory $packageDir');
  }
  command.write(' ${addDescriptions.join(' ')}');
  return command.toString();
}

String _upgradeMajorVersionsCommand(Entrypoint entrypoint, [String? package]) {
  final command = StringBuffer('$topLevelProgram pub upgrade');
  final currentDir = p.canonicalize(p.current);
  final workspaceDir = p.canonicalize(p.absolute(entrypoint.workspaceRoot.dir));
  if (!p.equals(currentDir, workspaceDir)) {
    final relativeWorkspaceDir = escapeShellArgument(
      p.normalize(p.relative(entrypoint.workspaceRoot.dir)),
    );
    command.write(' --directory $relativeWorkspaceDir');
  }
  command.write(' --major-versions');
  if (package != null) {
    command.write(' $package');
  }
  return command.toString();
}

bool _needsDirectoryOption(Package package) {
  final currentDir = p.canonicalize(p.current);
  final packageDir = p.canonicalize(p.absolute(package.dir));
  return !p.equals(currentDir, packageDir) &&
      !p.isWithin(packageDir, currentDir);
}

bool _samePackage(Package a, Package b) {
  return p.equals(
    p.canonicalize(p.absolute(a.dir)),
    p.canonicalize(p.absolute(b.dir)),
  );
}

class _ResolutionContext {
  final Entrypoint entrypoint;
  final SolveType type;
  final Iterable<String> unlock;
  final SystemCache cache;
  _ResolutionContext({
    required this.entrypoint,
    required this.type,
    required this.cache,
    required this.unlock,
  });

  /// If [cause] mentions an sdk, attempt resolving using another released
  /// version of Flutter/Dart. Return that as a suggestion if found.
  Future<_ResolutionSuggestion?> suggestSdkUpdate(
    SdkIncompatibilityCause cause,
  ) async {
    final sdkName = cause.sdk.identifier;
    if (!(sdkName == 'dart' || (sdkName == 'flutter' && runningFromFlutter))) {
      // Only make sdk upgrade suggestions for Flutter and Dart.
      return null;
    }

    final constraint = cause.constraint;
    if (constraint == null) return null;

    // Find the most relevant Flutter release fulfilling the constraint.
    final bestRelease = await inferBestFlutterRelease({
      cause.sdk.identifier: constraint,
    });
    if (bestRelease == null) return null;
    final result = await _tryResolve(
      entrypoint.workspaceRoot,
      sdkOverrides: {
        'dart': bestRelease.dartVersion,
        'flutter': bestRelease.flutterVersion,
      },
    );
    if (result == null) {
      return null;
    }
    return _ResolutionSuggestion(
      runningFromFlutter
          ? '* Try using the Flutter SDK version: '
              '${bestRelease.flutterVersion}. '
          :
          // Here we assume that any Dart version included in a Flutter
          // release can also be found as a released Dart SDK.
          '* Try using the Dart SDK version: ${bestRelease.dartVersion}. See https://dart.dev/get-dart.',
    );
  }

  /// Attempt another resolution with a relaxed constraint on [name]. If that
  /// resolves, suggest upgrading to that version.
  Future<_ResolutionSuggestion?> suggestSinglePackageUpdate(String name) async {
    final ranges = _workspaceDependencyRanges(name).toList();
    if (ranges.isEmpty) return null;

    if (ranges.any((r) => r.range.description is! HostedDescription)) {
      return null;
    }

    final packagesToRelax = ranges.map((r) => r.package).toSet();
    final relaxedWorkspace = entrypoint.workspaceRoot.transformWorkspace(
      (workspacePackage) =>
          packagesToRelax.any((p) => _samePackage(p, workspacePackage))
              ? stripVersionBounds(
                workspacePackage.pubspec,
                stripOnly: [name],
                stripLowerBound: true,
              )
              : workspacePackage.pubspec,
    );

    final result = await _tryResolve(relaxedWorkspace);
    if (result == null) {
      return null;
    }
    final resolvingPackage = result.packages.firstWhere((p) => p.name == name);

    final suggestions =
        <({String command, String action, Package package, bool isDev})>[];
    var priority = 1;

    for (final (:package, :range, :isDev) in ranges) {
      if (range.constraint.allows(resolvingPackage.version)) {
        continue;
      }

      final addDescription = packageAddDescription(
        package,
        resolvingPackage,
        originalRange: range,
        isDev: isDev,
      );
      if (addDescription == null) return null;

      final command = _packageAddCommand(entrypoint, package, [addDescription]);

      var action = 'updating';
      final originalConstraint = range.constraint;
      if (originalConstraint is VersionRange) {
        final min = originalConstraint.min;
        if (min != null) {
          if (resolvingPackage.version < min) {
            priority = max(priority, 3);
            action = 'downgrading';
          } else {
            priority = max(priority, 2);
            action = 'upgrading';
          }
        }
      }
      suggestions.add((
        command: command,
        action: action,
        package: package,
        isDev: isDev,
      ));
    }

    if (suggestions.isEmpty) return null;

    if (suggestions.length == 1) {
      final suggestion = suggestions.first;
      final lead =
          suggestion.action == 'downgrading'
              ? 'Consider downgrading your constraint'
              : suggestion.action == 'upgrading'
              ? 'Try upgrading your constraint'
              : 'Try updating your constraint';
      return _ResolutionSuggestion(
        '* $lead on $name: ${suggestion.command}',
        priority: priority,
      );
    }

    final anyDowngrade = suggestions.any((s) => s.action == 'downgrading');
    if (anyDowngrade) {
      final buffer = StringBuffer(
        '* Try manually updating your constraints on $name:',
      );
      for (final s in suggestions) {
        final relativePubspec = p.normalize(p.relative(s.package.pubspecPath));
        final depKey = s.isDev ? 'dev_dependencies' : 'dependencies';
        final newConstraint = VersionConstraint.compatibleWith(
          resolvingPackage.version,
        );
        buffer.writeln();
        buffer.write(
          '  In $relativePubspec: set $depKey -> $name to $newConstraint',
        );
      }
      return _ResolutionSuggestion(buffer.toString(), priority: priority);
    } else {
      return _ResolutionSuggestion(
        '* Try upgrading your constraints on $name: '
        '${_upgradeMajorVersionsCommand(entrypoint, name)}',
        priority: priority,
      );
    }
  }

  /// Attempt resolving with all version constraints relaxed. If that resolves,
  /// return a corresponding suggestion to update.
  Future<_ResolutionSuggestion?> suggestUnlockingAll({
    required bool stripLowerBound,
  }) async {
    final originalWorkspace = entrypoint.workspaceRoot.transitiveWorkspace;
    final relaxedWorkspace = entrypoint.workspaceRoot.transformWorkspace(
      (package) =>
          stripVersionBounds(package.pubspec, stripLowerBound: stripLowerBound),
    );

    final result = await _tryResolve(relaxedWorkspace);
    if (result == null) {
      return null;
    }
    final resolvedPackages = {for (final id in result.packages) id.name: id};
    final updatedPackageVersions =
        <({Package package, PackageRange range, PackageId id, bool isDev})>[];
    for (final package in originalWorkspace) {
      void addUpdate(PackageRange range, {required bool isDev}) {
        final id = resolvedPackages[range.name];
        if (id != null) {
          updatedPackageVersions.add((
            package: package,
            range: range,
            id: id,
            isDev: isDev,
          ));
        }
      }

      for (final range in package.dependencies.values) {
        addUpdate(range, isDev: false);
      }
      for (final range in package.devDependencies.values) {
        addUpdate(range, isDev: true);
      }
    }
    if (stripLowerBound && updatedPackageVersions.length > 5) {
      // Too complex, don't suggest.
      return null;
    }
    if (stripLowerBound) {
      if (updatedPackageVersions.isEmpty) return null;
      final package = updatedPackageVersions.first.package;
      if (updatedPackageVersions.any((update) {
        return !_samePackage(update.package, package);
      })) {
        return null;
      }
      updatedPackageVersions.sort((a, b) => a.id.name.compareTo(b.id.name));
      final formattedConstraints = <String>[];
      for (final update in updatedPackageVersions) {
        final description = packageAddDescription(
          package,
          update.id,
          originalRange: update.range,
          isDev: update.isDev,
        );
        if (description == null) return null;
        formattedConstraints.add(description);
      }
      final command = _packageAddCommand(
        entrypoint,
        package,
        formattedConstraints,
      );
      return _ResolutionSuggestion(
        '* Try updating the following constraints: $command',
        priority: 4,
      );
    } else {
      return _ResolutionSuggestion(
        '* Try an upgrade of your constraints: '
        '${_upgradeMajorVersionsCommand(entrypoint)}',
        priority: 4,
      );
    }
  }

  /// Attempt resolving
  Future<SolveResult?> _tryResolve(
    Package package, {
    Map<String, Version> sdkOverrides = const {},
  }) async {
    try {
      return await resolveVersions(
        type,
        cache,
        package,
        sdkOverrides: sdkOverrides,
        lockFile: entrypoint.lockFile,
        unlock: unlock,
      );
    } on SolveFailure {
      return null;
    }
  }

  Iterable<({Package package, PackageRange range, bool isDev})>
  _workspaceDependencyRanges(String name) sync* {
    for (final package in entrypoint.workspaceRoot.transitiveWorkspace) {
      final dependency = package.dependencies[name];
      if (dependency != null) {
        yield (package: package, range: dependency, isDev: false);
      }
      final devDependency = package.devDependencies[name];
      if (devDependency != null) {
        yield (package: package, range: devDependency, isDev: true);
      }
    }
  }
}
