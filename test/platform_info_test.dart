// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:pub/src/platform_info.dart';
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';

void main() {
  test('overriding works', () async {
    final originalOS = platform.operatingSystem;
    final fakePlatform = PlatformInfo.override(
      environment: {'FOO': 'BAR'},
      executable: 'dart_fake',
      isAndroid: false,
      isFuchsia: false,
      isIOS: false,
      isLinux: false,
      isMacOS: false,
      isWindows: true,
      lineTerminator: '\r\n',
      operatingSystem: 'windows',
      pathSeparator: '\\',
      resolvedExecutable: 'C:\\bin\\dart_fake',
      version: '3.0.0-fake',
      script: Uri.file('C:\\bin\\dart_fake.dart'),
      numberOfProcessors: 2,
    );

    await withPlatform(() async {
      expect(platform.operatingSystem, 'windows');
      expect(platform.isWindows, isTrue);
      expect(platform.isLinux, isFalse);
      expect(platform.environment['FOO'], 'BAR');
      expect(platform.executable, 'dart_fake');
      expect(platform.pathSeparator, '\\');
    }, platform: fakePlatform);

    expect(platform.operatingSystem, originalOS);
  }, testOn: 'vm');

  test('overriding works (also in browser)', () async {
    final fakePlatform = PlatformInfo.override(
      environment: {'FOO': 'BAR'},
      executable: 'dart_fake',
      isAndroid: false,
      isFuchsia: false,
      isIOS: false,
      isLinux: false,
      isMacOS: false,
      isWindows: true,
      lineTerminator: '\r\n',
      operatingSystem: 'windows',
      pathSeparator: '\\',
      resolvedExecutable: 'C:\\bin\\dart_fake',
      version: '3.0.0-fake',
      script: Uri.file('C:\\bin\\dart_fake.dart'),
      numberOfProcessors: 2,
    );

    await withPlatform(() async {
      expect(platform.operatingSystem, 'windows');
      expect(platform.isWindows, isTrue);
      expect(platform.isLinux, isFalse);
      expect(platform.environment['FOO'], 'BAR');
      expect(platform.executable, 'dart_fake');
      expect(platform.pathSeparator, '\\');
    }, platform: fakePlatform);
  });

  test('dart:io Platform is not used outside platform_info.dart', () async {
    // This test exists to ensure that we don't use Platform from dart:io
    // unintentionally. We only want to use it in lib/src/platform_info.dart!
    // Everywhere else we should rely on `platform` from here.
    // This way, we can overrride the platform when we need to.
    final allowListedFiles = [
      'lib/src/platform_info.dart',
      'test/platform_info_test.dart',
    ];

    final root = p.normalize(p.absolute('.'));
    final collection = AnalysisContextCollection(
      includedPaths: [p.join(root, 'lib')],
    );

    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;

        // Skip allow listed files
        if (allowListedFiles.contains(p.relative(filePath, from: root))) {
          continue;
        }

        final result = await context.currentSession.getResolvedUnit(filePath);
        if (result is ResolvedUnitResult) {
          SourceSpan? first;
          result.unit.accept(
            ForEachIdentifier((element) {
              if (first == null &&
                  element.element?.name == 'Platform' &&
                  element.element?.library?.name == 'dart.io') {
                first = SourceFile.fromString(
                  result.content,
                  url: filePath,
                ).span(element.offset, element.end);
              }
            }),
          );
          if (first != null) {
            fail(
              first!.message(
                'Found Platform usage from dart:io, '
                'use lib/src/platform_info.dart instead.',
              ),
            );
          }
        }
      }
    }
  }, testOn: 'vm');
}

final class ForEachIdentifier extends GeneralizingAstVisitor<void> {
  final void Function(Identifier element) _visitIdentifier;
  ForEachIdentifier(this._visitIdentifier);

  @override
  void visitComment(Comment node) {
    // Do not walk into comments! They are allowed to reference Platform!
  }

  @override
  void visitIdentifier(Identifier element) {
    _visitIdentifier(element);
    super.visitIdentifier(element);
  }
}
