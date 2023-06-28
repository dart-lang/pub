// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';

import '../dart.dart';
import '../exceptions.dart';
import '../io.dart';
import '../package_name.dart';
import '../validator.dart';

/// Gives a warning when releasing a breaking version containing @Deprecated
/// annotations.
class RemoveDeprecatedOnBreakingReleaseValidator extends Validator {
  @override
  Future<void> validate() async {
    final hostedSource = entrypoint.cache.hosted;
    List<PackageId> existingVersions;
    try {
      existingVersions = await entrypoint.cache.getVersions(
        hostedSource.refFor(entrypoint.root.name, url: serverUrl.toString()),
      );
    } on PackageNotFoundException {
      existingVersions = [];
    }
    existingVersions.sort((a, b) => a.version.compareTo(b.version));

    final currentVersion = entrypoint.root.pubspec.version;

    final previousRelease = existingVersions
        .lastWhereOrNull((id) => id.version < entrypoint.root.version);

    if (previousRelease != null &&
        !VersionConstraint.compatibleWith(previousRelease.version)
            .allows(currentVersion)) {
      // A breaking release.
      final packagePath = p.normalize(p.absolute(entrypoint.rootDir));
      final analysisContextManager = AnalysisContextManager(packagePath);
      for (var file in filesBeneath('lib', recursive: true).where(
        (file) =>
            p.extension(file) == '.dart' &&
            !p.isWithin(p.join(entrypoint.root.dir, 'lib', 'src'), file),
      )) {
        final unit = analysisContextManager.parse(file);
        for (final declaration in unit.declarations) {
          warnIfDeprecated(declaration, file);
          if (declaration is ClassOrAugmentationDeclaration) {
            for (final member in declaration.members) {
              warnIfDeprecated(member, file);
            }
          }
          if (declaration is MixinOrAugmentationDeclaration) {
            for (final member in declaration.members) {
              warnIfDeprecated(member, file);
            }
          }
          if (declaration is EnumDeclaration) {
            for (final member in declaration.members) {
              warnIfDeprecated(member, file);
            }
          }
        }
      }
    }
  }

  /// Warn if [declaration] has a This is a syntactic check only, and therefore
  /// imprecise but much faster than doing resolution.
  ///
  /// Cases where this will break down:
  /// ```
  /// const d = Deprecated('Please don't use');
  /// @d class P {} // False negative.
  /// ```
  ///
  /// ```
  /// import 'dart:core as core';
  /// import 'mylib.dart' show Deprecated;
  ///
  /// @Deprecated() class A {} // False positive
  /// ```
  void warnIfDeprecated(Declaration declaration, String file) {
    for (final commentOrAnnotation in declaration.sortedCommentAndAnnotations) {
      if (commentOrAnnotation
          case Annotation(name: SimpleIdentifier(name: 'Deprecated'))) {
        warnings.add(
          SourceFile.fromString(readTextFile(file), url: file)
              .span(commentOrAnnotation.offset,
                  commentOrAnnotation.offset + commentOrAnnotation.length)
              .message(
                'You are about to publish a breaking release. Consider removing this deprecated declaration.',
              ),
        );
      }
    }
  }
}
