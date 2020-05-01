// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';

import 'package:pub_semver/pub_semver.dart';
import 'package:path/path.dart' as path;

import 'entrypoint.dart';
import 'io.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'solver.dart';
import 'source/cached.dart';
import 'source/path.dart';
import 'system_cache.dart';

enum NullSafetyCompliance {
  /// This package and all dependencies opted into null safety.
  compliant,

  /// This package opted into null safety, but some file or dependency is not
  /// opted in.
  apiOnly,

  /// This package did not opt-in to null safety yet.
  notCompliant,

  /// The resolution failed. Or some dart file in a dependency
  /// doesn't parse.
  analysisFailed,
}

class NullSafetyAnalysis {
  final SystemCache _systemCache;

  /// A cache of the analysis done for a single package-version, not taking
  /// dependencies into account. (Only the sdk constraint and no-files-opt-out).
  ///
  /// This allows us to reuse the analysis of the same package-version when
  /// used as a dependency from different packages.
  ///
  /// Furthermore by awaiting the Future stored here, we avoid race-conditions
  /// from downloading the same package-version into [_systemCache]
  /// simultaneously when doing concurrent analyses.
  final Map<PackageId, Future<NullSafetyCompliance>>
      _packageInternallyGoodCache = {};
  static final _firstVersionWithNullSafety = Version.parse('2.10.0');

  NullSafetyAnalysis(SystemCache systemCache) : _systemCache = systemCache;

  /// Returns true if package version [packageId] and all its non-dev
  /// dependencies (transitively) have a language version >= 2.10, and no files
  /// in lib/ of  these packages opt out to a pre-2.10 language version.
  ///
  /// This will do a full resolution of that package's import graph, and also
  /// download the package and all dependencies into [cache].
  ///
  /// To avoid race conditions on downloading to the cache, only one instance
  /// should be computing nullSafetyCompliance simultaneously with the same
  /// cache.
  Future<NullSafetyCompliance> nullSafetyCompliance(PackageId packageId) async {
    return await withTempDir((tempPath) async {
      final importingPubspec = {
        'name': '${packageId.name}_importer',
        'dependencies': {
          packageId.name: {
            packageId.source.name: packageId.source is PathSource
                ? packageId.description['path']
                : packageId.description,
            'version': packageId.version.toString(),
          }
        }
      };

      writeTextFile(
          path.join(tempPath, 'pubspec.yaml'), json.encode(importingPubspec));
      final importingEntrypoint = Entrypoint(tempPath, _systemCache);
      SolveResult result;
      try {
        result = await resolveVersions(
          SolveType.GET,
          _systemCache,
          importingEntrypoint.root,
        );
      } on SolveFailure {
        return NullSafetyCompliance.analysisFailed;
      }

      final analysisSession = ContextBuilder()
          .createContext(
            contextRoot: ContextLocator().locateRoots(
              includedPaths: [tempPath],
            ).first,
          )
          .currentSession;

      var allPackagesGood = true;
      for (final dependencyId in result.packages) {
        if (dependencyId.name == importingEntrypoint.root.name) continue;

        final packageInternallyGood = await _packageInternallyGoodCache
            .putIfAbsent(dependencyId, () async {
          final boundSource = dependencyId.source.bind(_systemCache);
          final pubspec = await boundSource.describe(dependencyId);
          final languageVersion = _languageVersion(pubspec);
          if (languageVersion == null ||
              languageVersion < _firstVersionWithNullSafety) {
            return NullSafetyCompliance.notCompliant;
          }

          if (boundSource is CachedSource) {
            /// TODO(sigurdm): Should we set metadata here?
            await boundSource.downloadToSystemCache(dependencyId);
          }
          final libDir = path.absolute(path.normalize(
              path.join(boundSource.getDirectory(dependencyId), 'lib')));
          if (!dirExists(libDir)) {}
          for (final file in listDir(libDir,
              recursive: true, includeDirs: false, includeHidden: true)) {
            if (file.endsWith('.dart')) {
              final unitResult =
                  analysisSession.getParsedUnit(path.normalize(file));
              if (unitResult == null || unitResult.errors.isNotEmpty) {
                return NullSafetyCompliance.analysisFailed;
              }
              if (unitResult.isPart) continue;
              final languageVersionToken = unitResult.unit.languageVersionToken;
              if (languageVersionToken == null) continue;
              if (Version(languageVersionToken.major,
                      languageVersionToken.minor, 0) <
                  _firstVersionWithNullSafety) {
                return NullSafetyCompliance.notCompliant;
              }
            }
          }
          return NullSafetyCompliance.compliant;
        });
        assert(packageInternallyGood != null);
        if (packageInternallyGood == NullSafetyCompliance.analysisFailed) {
          return NullSafetyCompliance.analysisFailed;
        }
        if (packageInternallyGood == NullSafetyCompliance.notCompliant) {
          allPackagesGood = false;
        }
      }
      if (allPackagesGood) return NullSafetyCompliance.compliant;
      final rootLanguageVersion = _languageVersion(
          await packageId.source.bind(_systemCache).describe(packageId));
      if (rootLanguageVersion != null &&
          rootLanguageVersion >= _firstVersionWithNullSafety) {
        return NullSafetyCompliance.apiOnly;
      }
      return NullSafetyCompliance.notCompliant;
    });
  }

  /// Returns the language version specified by the dart sdk
  Version _languageVersion(Pubspec pubspec) {
    final sdkConstraint = pubspec.sdkConstraints['dart'];
    if (sdkConstraint is VersionRange) {
      final rangeMin = sdkConstraint.min;
      if (rangeMin == null) return null;
      return Version(rangeMin.major, rangeMin.minor, 0);
    }
    return null;
  }
}
