import 'package:pub_semver/pub_semver.dart';

import '../command_runner.dart';
import '../entrypoint.dart';
import '../flutter_releases.dart';
import '../io.dart';
import '../lock_file.dart';
import '../package.dart';
import '../package_name.dart';
import '../pubspec_utils.dart';
import '../solver.dart';
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
    final result = await tryResolve(type, cache, entrypoint.root,
        lockFile: entrypoint.lockFile,
        unlock: unlock,
        sdkOverrides: {
          'dart': bestRelease.dartVersion,
          'flutter': bestRelease.flutterVersion
        });
    if (result != null) {
      return _ResolutionSuggestion(
        runningFromFlutter
            ? '* Try using the Flutter SDK version: ${bestRelease.flutterVersion}. '
            :
            // Here we assume that any Dart version included in a Flutter
            // release can also be found as a released Dart SDK.
            '* Try using the Dart SDK version: ${bestRelease.dartVersion}. See https://dart.dev/get-dart.',
      );
    }
    return null;
  }

  Future<_ResolutionSuggestion?> suggestSinglePackageUpdate(String name) async {
    final originalConstraint = (entrypoint.root.dependencies[name] ??
            entrypoint.root.devDependencies[name])
        ?.constraint;
    if (originalConstraint != null) {
      final relaxedPubspec = stripVersionBounds(entrypoint.root.pubspec,
          stripOnly: [name], stripLowerBound: true);

      final result = await tryResolve(
          type, cache, Package.inMemory(relaxedPubspec),
          lockFile: entrypoint.lockFile, unlock: unlock);
      if (result != null) {
        final resolvingPackage =
            result.packages.firstWhere((p) => p.name == name);

        final addDescription =
            packageAddDescription(entrypoint, resolvingPackage);

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
    }
    return null;
  }

  Future<_ResolutionSuggestion?> suggestUnlockingAll(
      {required bool stripLowerBound}) async {
    final originalPubspec = entrypoint.root.pubspec;
    final relaxedPubspec =
        stripVersionBounds(originalPubspec, stripLowerBound: stripLowerBound);

    final result = await tryResolve(
        type, cache, Package.inMemory(relaxedPubspec),
        lockFile: entrypoint.lockFile, unlock: unlock);
    if (result != null) {
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
            priority: 4);
      } else {
        return _ResolutionSuggestion(
            '* Try an upgrade of your constraints: $topLevelProgram pub upgrade --major-versions',
            priority: 4);
      }
    }
    return null;
  }

  final visited = <String>{};
  final stopwatch = Stopwatch()..start();
  final suggestions = <_ResolutionSuggestion>[];
  void addSuggestion(_ResolutionSuggestion? suggestion) {
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
      addSuggestion(await suggestSdkUpdate(cause));
    } else {
      for (final term in externalIncompatibility.terms) {
        final name = term.package.name;

        if (!visited.add(name)) {
          continue;
        }
        addSuggestion(await suggestSinglePackageUpdate(name));
      }
    }
  }
  if (suggestions.isEmpty) {
    addSuggestion(await suggestUnlockingAll(stripLowerBound: true) ??
        await suggestUnlockingAll(stripLowerBound: false));
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

Future<SolveResult?> tryResolve(SolveType type, SystemCache cache, Package root,
    {LockFile? lockFile,
    Iterable<String> unlock = const [],
    Map<String, Version> sdkOverrides = const {}}) async {
  try {
    return await resolveVersions(type, cache, root,
        lockFile: lockFile, sdkOverrides: sdkOverrides);
  } on SolveFailure {
    return null;
  }
}

String packageAddDescription(Entrypoint entrypoint, PackageId id) {
  final name = id.name;
  final isDev = entrypoint.root.pubspec.devDependencies.containsKey(name);
  final constraint = VersionConstraint.compatibleWith(id.version);
  final devPart = isDev ? 'dev:' : '';
  return '$devPart$name:$constraint';
}
