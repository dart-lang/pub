// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import '../io.dart';
import '../path.dart';
import '../validator.dart';

/// Reports a hint if a published `analysis_options.yaml` file includes a local
/// configuration file that is not part of the published package.
///
/// When an included file is outside the package (or excluded via `.pubignore`
/// or `.gitignore`), the published package is not self-contained. This can
/// cause different analysis or formatting results on `pub.dev` (for example,
/// if the missing file disables lints/errors, excludes files, or configures
/// formatter options), or `include_file_not_found` warnings if the published
/// archive is unpacked and analyzed directly.
final class AnalysisOptionsValidator extends Validator {
  @override
  Future<void> validate() async {
    final packageDir = p.canonicalize(package.dir);
    final publishedFiles = <String, String>{
      for (final file in files) p.canonicalize(file): file,
    };

    final candidates = [
      for (final entry in publishedFiles.entries)
        if (p.basename(entry.value) == 'analysis_options.yaml') entry.key,
    ]..sort();

    final visited = <String>{};
    for (final candidate in candidates) {
      _validateAnalysisOptionsFile(
        candidate,
        packageDir: packageDir,
        publishedFiles: publishedFiles,
        visited: visited,
      );
    }
  }

  void _validateAnalysisOptionsFile(
    String canonicalFilePath, {
    required String packageDir,
    required Map<String, String> publishedFiles,
    required Set<String> visited,
  }) {
    if (!visited.add(canonicalFilePath)) return;
    if (!fileExists(canonicalFilePath)) return;

    final String contents;
    try {
      contents = readTextFile(canonicalFilePath);
    } on IOException {
      return;
    }

    final Object? yaml;
    try {
      yaml = loadYaml(contents);
    } on FormatException {
      return;
    }

    if (yaml is! Map) return;

    final include = yaml['include'];
    final includes = switch (include) {
      final String uri => [uri],
      final List<Object?> list => [
        for (final item in list)
          if (item is String) item,
      ],
      _ => const <String>[],
    };

    final originalFilePath =
        publishedFiles[canonicalFilePath] ?? canonicalFilePath;

    for (final includeUri in includes) {
      final resolution = resolveInclude(
        includeUri,
        fromFile: canonicalFilePath,
        packageDir: packageDir,
      );

      switch (resolution.kind) {
        case IncludeResolutionKind.ignored:
          continue;
        case IncludeResolutionKind.outsidePackage:
          final relOptionsPath = p.relative(
            originalFilePath,
            from: package.dir,
          );
          hints.add(
            'The analysis options file `$relOptionsPath` includes '
            '`$includeUri`, which points to a file outside the package.\n'
            'Files outside the package are not included in the published '
            'package.\n\n'
            'Consider using a package URI '
            '(e.g. `package:lints/recommended.yaml`), inlining the options, '
            'or excluding the analysis options file with `.pubignore`.',
          );
        case IncludeResolutionKind.absoluteInPackage:
          final relOptionsPath = p.relative(
            originalFilePath,
            from: package.dir,
          );
          hints.add(
            'The analysis options file `$relOptionsPath` includes '
            '`$includeUri` using an absolute path.\n'
            'Absolute paths are not portable across machines.\n\n'
            'Consider using a relative path, a package URI '
            '(e.g. `package:lints/recommended.yaml`), inlining the options, '
            'or excluding the analysis options file with `.pubignore`.',
          );
          final targetPath = resolution.targetPath!;
          if (publishedFiles.containsKey(targetPath)) {
            _validateAnalysisOptionsFile(
              targetPath,
              packageDir: packageDir,
              publishedFiles: publishedFiles,
              visited: visited,
            );
          }
        case IncludeResolutionKind.relativeInPackage:
          final targetPath = resolution.targetPath!;
          if (publishedFiles.containsKey(targetPath)) {
            _validateAnalysisOptionsFile(
              targetPath,
              packageDir: packageDir,
              publishedFiles: publishedFiles,
              visited: visited,
            );
          } else if (fileExists(targetPath)) {
            final relOptionsPath = p.relative(
              originalFilePath,
              from: package.dir,
            );
            hints.add(
              'The analysis options file `$relOptionsPath` includes '
              '`$includeUri`, which is not included in the published '
              'package.\n\n'
              'Consider using a package URI '
              '(e.g. `package:lints/recommended.yaml`), inlining the options, '
              'or updating `.pubignore` / `.gitignore`.',
            );
          }
      }
    }
  }

  /// Resolves an `include` entry from [fromFile] relative to [packageDir].
  ///
  /// Both [fromFile] and [packageDir] must be canonicalized paths.
  @visibleForTesting
  static ({IncludeResolutionKind kind, String? targetPath}) resolveInclude(
    String includeUri, {
    required String fromFile,
    required String packageDir,
  }) {
    if (includeUri.trim().isEmpty) {
      return (kind: IncludeResolutionKind.ignored, targetPath: null);
    }

    // Check platform absolute paths before URI scheme parsing: on Windows,
    // `Uri.tryParse(r'C:\foo.yaml')` parses `c:` as a URI scheme.
    if (p.isAbsolute(includeUri)) {
      final targetPath = p.canonicalize(includeUri);
      final isInside = p.isWithin(packageDir, targetPath);
      return (
        kind:
            isInside
                ? IncludeResolutionKind.absoluteInPackage
                : IncludeResolutionKind.outsidePackage,
        targetPath: targetPath,
      );
    }

    final parsedUri = Uri.tryParse(includeUri);
    if (parsedUri != null && parsedUri.scheme == 'file') {
      final String targetPath;
      try {
        targetPath = p.canonicalize(p.fromUri(parsedUri));
      } on FormatException {
        return (kind: IncludeResolutionKind.outsidePackage, targetPath: null);
      }
      final isInside = p.isWithin(packageDir, targetPath);
      return (
        kind:
            isInside
                ? IncludeResolutionKind.absoluteInPackage
                : IncludeResolutionKind.outsidePackage,
        targetPath: targetPath,
      );
    }

    // Ignore non-file URI schemes such as `package:lints/recommended.yaml`.
    if (parsedUri != null && parsedUri.hasScheme) {
      return (kind: IncludeResolutionKind.ignored, targetPath: null);
    }

    final relDir = p.relative(p.dirname(fromFile), from: packageDir);
    final relTarget = p.normalize(p.join(relDir, includeUri));
    final relParts = p.split(relTarget);
    final escapesPackage = relParts.isNotEmpty && relParts.first == '..';

    final targetPath = p.canonicalize(p.join(p.dirname(fromFile), includeUri));
    if (escapesPackage || !p.isWithin(packageDir, targetPath)) {
      return (
        kind: IncludeResolutionKind.outsidePackage,
        targetPath: targetPath,
      );
    }

    return (
      kind: IncludeResolutionKind.relativeInPackage,
      targetPath: targetPath,
    );
  }
}

/// Classification of an `include:` target in an `analysis_options.yaml` file.
@visibleForTesting
enum IncludeResolutionKind {
  ignored,
  relativeInPackage,
  absoluteInPackage,
  outsidePackage,
}
