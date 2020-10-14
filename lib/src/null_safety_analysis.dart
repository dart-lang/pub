// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/analysis/context_builder.dart';
import 'package:analyzer/dart/analysis/context_locator.dart';
import 'package:cli_util/cli_util.dart';
import 'package:source_span/source_span.dart';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'io.dart';
import 'language_version.dart';
import 'package.dart';
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
  mixed,

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
  final Map<PackageId, Future<NullSafetyAnalysisResult>>
      _packageInternallyGoodCache = {};

  NullSafetyAnalysis(SystemCache systemCache) : _systemCache = systemCache;

  /// Returns true if package version [packageId] and all its non-dev
  /// dependencies (transitively) have a language version >= 2.12, and no files
  /// in lib/ of  these packages opt out to a pre-2.12 language version.
  ///
  /// This will do a full resolution of that package's import graph, and also
  /// download the package and all dependencies into [cache].
  ///
  /// To avoid race conditions on downloading to the cache, only one instance
  /// should be computing nullSafetyCompliance simultaneously with the same
  /// cache.
  ///
  /// If [packageId] is a relative path dependency [containingPath] must be
  /// provided with an absolute path to resolve it against.
  Future<NullSafetyAnalysisResult> nullSafetyCompliance(PackageId packageId,
      {String containingPath}) async {
    // A space in the name prevents clashes with other package names.
    final rootName = '${packageId.name} importer';
    final root = Package.inMemory(Pubspec(rootName,
        fields: {
          'dependencies': {
            packageId.name: {
              packageId.source.name: packageId.source is PathSource
                  ? (packageId.description['relative']
                      ? path.join(containingPath, packageId.description['path'])
                      : packageId.description['path'])
                  : packageId.description,
              'version': packageId.version.toString(),
            }
          }
        },
        sources: _systemCache.sources));

    final rootPubspec =
        await packageId.source.bind(_systemCache).describe(packageId);
    final rootLanguageVersion = rootPubspec.languageVersion;
    if (!rootLanguageVersion.supportsNullSafety) {
      final span =
          _tryGetSpanFromYamlMap(rootPubspec.fields['environment'], 'sdk');
      final where = span == null
          ? 'in the sdk constraint in the enviroment key in pubspec.yaml.'
          : 'in pubspec.yaml: \n${span.highlight()}';
      return NullSafetyAnalysisResult(
        NullSafetyCompliance.notCompliant,
        'Is not opting in to null safety $where',
      );
    }

    SolveResult result;
    try {
      result = await resolveVersions(
        SolveType.GET,
        _systemCache,
        root,
      );
    } on SolveFailure catch (e) {
      return NullSafetyAnalysisResult(NullSafetyCompliance.analysisFailed,
          'Could not resolve constraints: $e');
    }

    NullSafetyAnalysisResult firstBadPackage;
    for (final dependencyId in result.packages) {
      if (dependencyId.name == root.name) continue;

      final packageInternalAnalysis =
          await _packageInternallyGoodCache.putIfAbsent(dependencyId, () async {
        final boundSource = dependencyId.source.bind(_systemCache);
        final pubspec = await boundSource.describe(dependencyId);
        final languageVersion = pubspec.languageVersion;
        if (languageVersion == null || !languageVersion.supportsNullSafety) {
          final span =
              _tryGetSpanFromYamlMap(pubspec.fields['environment'], 'sdk');
          final where = span == null
              ? 'in the sdk constraint in the enviroment key in its pubspec.yaml.'
              : 'in its pubspec.yaml:\n${span.highlight()}';
          return NullSafetyAnalysisResult(
            NullSafetyCompliance.notCompliant,
            'package:${dependencyId.name} is not opted into null safety $where',
          );
        }

        if (boundSource is CachedSource) {
          // TODO(sigurdm): Consider using withDependencyType here.
          await boundSource.downloadToSystemCache(dependencyId);
        }
        final packageDir = boundSource.getDirectory(dependencyId);
        final libDir =
            path.absolute(path.normalize(path.join(packageDir, 'lib')));
        if (dirExists(libDir)) {
          final analysisSession = ContextBuilder()
              .createContext(
                sdkPath: getSdkPath(),
                contextRoot: ContextLocator().locateRoots(
                  includedPaths: [packageDir],
                ).first,
              )
              .currentSession;

          for (final file in listDir(libDir,
              recursive: true, includeDirs: false, includeHidden: true)) {
            if (file.endsWith('.dart')) {
              final fileUrl =
                  'package:${dependencyId.name}/${path.relative(file, from: libDir)}';
              final unitResult =
                  analysisSession.getParsedUnit(path.normalize(file));
              if (unitResult == null || unitResult.errors.isNotEmpty) {
                return NullSafetyAnalysisResult(
                    NullSafetyCompliance.analysisFailed,
                    'Could not analyze $fileUrl.');
              }
              if (unitResult.isPart) continue;
              final languageVersionToken = unitResult.unit.languageVersionToken;
              if (languageVersionToken == null) continue;
              final languageVersion = LanguageVersion.fromLanguageVersionToken(
                  languageVersionToken);
              if (!languageVersion.supportsNullSafety) {
                final sourceFile =
                    SourceFile.fromString(readTextFile(file), url: fileUrl);
                final span = sourceFile.span(languageVersionToken.offset,
                    languageVersionToken.offset + languageVersionToken.length);
                return NullSafetyAnalysisResult(
                    NullSafetyCompliance.notCompliant,
                    '$fileUrl is opting out of null safety:\n${span.highlight()}');
              }
            }
          }
        }
        return NullSafetyAnalysisResult(NullSafetyCompliance.compliant, null);
      });
      assert(packageInternalAnalysis != null);
      if (packageInternalAnalysis.compliance ==
          NullSafetyCompliance.analysisFailed) {
        return packageInternalAnalysis;
      }
      if (packageInternalAnalysis.compliance ==
          NullSafetyCompliance.notCompliant) {
        firstBadPackage ??= packageInternalAnalysis;
      }
    }

    if (firstBadPackage == null) {
      return NullSafetyAnalysisResult(NullSafetyCompliance.compliant, null);
    }
    if (firstBadPackage.compliance == NullSafetyCompliance.analysisFailed) {
      return firstBadPackage;
    }
    return NullSafetyAnalysisResult(
        NullSafetyCompliance.mixed, firstBadPackage.reason);
  }
}

class NullSafetyAnalysisResult {
  final NullSafetyCompliance compliance;

  /// `null` if compliance == [NullSafetyCompliance.compliant].
  final String reason;

  NullSafetyAnalysisResult(this.compliance, this.reason);
}

SourceSpan _tryGetSpanFromYamlMap(Object map, String key) {
  if (map is YamlMap) {
    return map.nodes[key]?.span;
  }
  return null;
}
