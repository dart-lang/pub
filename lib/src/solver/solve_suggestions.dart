import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../command_runner.dart';
import '../entrypoint.dart';
import '../flutter_releases.dart';
import '../io.dart';
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../pubspec_utils.dart';
import '../solver.dart';
import '../source/hosted.dart';
import '../system_cache.dart';
import 'incompatibility.dart';
import 'incompatibility_cause.dart';

/// Looks through the root-[incompability] of a solve-failure and tries to see if
/// the conflict could resolved by any of the following suggestions:
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
    if (stopwatch.elapsed > Duration(seconds: 3)) {
      // Never spend more than 3 seconds computing suggestions.
      break;
    }
    final cause = externalIncompatibility.cause;
    if (cause is SdkCause) {
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
  final tryOne = suggestions.length == 1
      ? 'You can try the following suggestion to make the pubspec resolve:'
      : 'You can try one of the following suggestions to make the pubspec resolve:';

  suggestions.sort((a, b) => a.priority.compareTo(b.priority));

  return '\n$tryOne\n${suggestions.take(5).map((e) => e.suggestion).join('\n')}';
}

class _ResolutionSuggestion {
  final String suggestion;
  final int priority;
  _ResolutionSuggestion(this.suggestion, {this.priority = 0});
}

String packageAddDescription(Entrypoint entrypoint, PackageId id) {
  final name = id.name;
  final isDev = entrypoint.root.pubspec.devDependencies.containsKey(name);
  final resolvedDescription = id.description;
  final String descriptor;
  final d = resolvedDescription.description.serializeForPubspec(
    containingDir: Directory.current
        .path // The add command will resolve file names relative to CWD.
    // This currently should have no implications as we don't create suggestions
    // for path-packages.
    ,
    languageVersion: entrypoint.root.pubspec.languageVersion,
  );
  if (d == null) {
    descriptor = VersionConstraint.compatibleWith(id.version).toString();
  } else {
    descriptor = json.encode({
      'version': VersionConstraint.compatibleWith(id.version).toString(),
      id.source.name: d
    });
  }

  final devPart = isDev ? 'dev:' : '';
  return '$devPart$name:${escapeShellArgument(descriptor)}';
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
  Future<_ResolutionSuggestion?> suggestSdkUpdate(SdkCause cause) async {
    final sdkName = cause.sdk.identifier;
    if (!(sdkName == 'dart' || (sdkName == 'flutter' && runningFromFlutter))) {
      // Only make sdk upgrade suggestions for Flutter and Dart.
      return null;
    }

    final constraint = cause.constraint;
    if (constraint == null) return null;

    /// Find the most relevant Flutter release fullfilling the constraint.
    final bestRelease =
        await inferBestFlutterRelease({cause.sdk.identifier: constraint});
    if (bestRelease == null) return null;
    final result = await _tryResolve(
      entrypoint.root.pubspec,
      sdkOverrides: {
        'dart': bestRelease.dartVersion,
        'flutter': bestRelease.flutterVersion
      },
    );
    if (result == null) {
      return null;
    }
    return _ResolutionSuggestion(
      runningFromFlutter
          ? '* Try using the Flutter SDK version: ${bestRelease.flutterVersion}. '
          :
          // Here we assume that any Dart version included in a Flutter
          // release can also be found as a released Dart SDK.
          '* Try using the Dart SDK version: ${bestRelease.dartVersion}. See https://dart.dev/get-dart.',
    );
  }

  /// Attempt another resolution with a relaxed constraint on [name]. If that
  /// resolves, suggest upgrading to that version.
  Future<_ResolutionSuggestion?> suggestSinglePackageUpdate(String name) async {
    final originalRange = entrypoint.root.dependencies[name] ??
        entrypoint.root.devDependencies[name];
    if (originalRange == null ||
        originalRange.description is! HostedDescription) {
      // We can only relax constraints on hosted dependencies.
      return null;
    }
    final originalConstraint = originalRange.constraint;
    final relaxedPubspec = stripVersionBounds(
      entrypoint.root.pubspec,
      stripOnly: [name],
      stripLowerBound: true,
    );

    final result = await _tryResolve(relaxedPubspec);
    if (result == null) {
      return null;
    }
    final resolvingPackage = result.packages.firstWhere((p) => p.name == name);

    final addDescription = packageAddDescription(entrypoint, resolvingPackage);

    var priority = 1;
    var suggestion =
        '* Try updating your constraint on $name: $topLevelProgram pub add $addDescription';
    if (originalConstraint is VersionRange) {
      final min = originalConstraint.min;
      if (min != null) {
        if (resolvingPackage.version < min) {
          priority = 3;
          suggestion =
              '* Consider downgrading your constraint on $name: $topLevelProgram pub add $addDescription';
        } else {
          priority = 2;
          suggestion =
              '* Try upgrading your constraint on $name: $topLevelProgram pub add $addDescription';
        }
      }
    }

    return _ResolutionSuggestion(suggestion, priority: priority);
  }

  /// Attempt resolving with all version constraints relaxed. If that resolves,
  /// return a corresponding suggestion to update.
  Future<_ResolutionSuggestion?> suggestUnlockingAll({
    required bool stripLowerBound,
  }) async {
    final originalPubspec = entrypoint.root.pubspec;
    final relaxedPubspec =
        stripVersionBounds(originalPubspec, stripLowerBound: stripLowerBound);

    final result = await _tryResolve(relaxedPubspec);
    if (result == null) {
      return null;
    }
    final updatedPackageVersions = <PackageId>[];
    for (final id in result.packages) {
      final originalConstraint = (originalPubspec.dependencies[id.name] ??
              originalPubspec.devDependencies[id.name])
          ?.constraint;
      if (originalConstraint != null) {
        updatedPackageVersions.add(id);
      }
    }
    if (stripLowerBound && updatedPackageVersions.length > 5) {
      // Too complex, don't suggest.
      return null;
    }
    if (stripLowerBound) {
      updatedPackageVersions.sort((a, b) => a.name.compareTo(b.name));
      final formattedConstraints = updatedPackageVersions
          .map((e) => packageAddDescription(entrypoint, e))
          .join(' ');
      return _ResolutionSuggestion(
        '* Try updating the following constraints: $topLevelProgram pub add $formattedConstraints',
        priority: 4,
      );
    } else {
      return _ResolutionSuggestion(
        '* Try an upgrade of your constraints: $topLevelProgram pub upgrade --major-versions',
        priority: 4,
      );
    }
  }

  /// Attempt resolving
  Future<SolveResult?> _tryResolve(
    Pubspec pubspec, {
    Map<String, Version> sdkOverrides = const {},
  }) async {
    try {
      return await resolveVersions(
        type,
        cache,
        Package.inMemory(pubspec),
        sdkOverrides: sdkOverrides,
        lockFile: entrypoint.lockFile,
        unlock: unlock,
      );
    } on SolveFailure {
      return null;
    }
  }
}
