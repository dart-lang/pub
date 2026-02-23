// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:path/path.dart' as path;
import 'package:pub/src/path.dart';
import 'package:test/test.dart';

void main() {
  test('withPathContext overrides p', () async {
    final customContext = path.Context(
      style: path.Style.posix,
      current: '/custom',
    );

    expect(p.current, isNot('/custom'));

    await withPathContext(() {
      expect(p.current, '/custom');
      expect(p.style, path.Style.posix);
      return Future<void>.value();
    }, pathContext: customContext);

    expect(p.current, isNot('/custom'));
  });

  test('withPathContext works with nested zones', () async {
    final context1 = path.Context(style: path.Style.posix, current: '/1');
    final context2 = path.Context(style: path.Style.posix, current: '/2');

    await withPathContext(() async {
      expect(p.current, '/1');
      await withPathContext(() async {
        expect(p.current, '/2');
      }, pathContext: context2);
      expect(p.current, '/1');
    }, pathContext: context1);
  });

  test('package:path/path.dart is only imported in lib/src/path.dart', () {
    final libDir = Directory('lib');
    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final offendingFiles = <String>[];

    for (final file in dartFiles) {
      if (p.basename(file.path) == 'path.dart' &&
          p.dirname(file.path).endsWith(p.join('lib', 'src'))) {
        continue;
      }

      final result = parseString(
        content: file.readAsStringSync(),
        featureSet: FeatureSet.latestLanguageVersion(),
      );

      final hasPathImport = result.unit.directives
          .whereType<ImportDirective>()
          .any(
            (directive) =>
                directive.uri.stringValue == 'package:path/path.dart',
          );

      if (hasPathImport) {
        offendingFiles.add(file.path);
      }
    }

    expect(
      offendingFiles,
      isEmpty,
      reason:
          'Files in lib/ should use the custom path context p from '
          'lib/src/path.dart instead of directly importing '
          'package:path/path.dart. This ensures that the path context can be '
          'overridden for testing using withPathContext.',
    );
  });
}
