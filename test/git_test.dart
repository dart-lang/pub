// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:pub/src/git.dart';
import 'package:test/test.dart';

import 'test_pub.dart';
import 'descriptor.dart';

void main() {
  test('splitZeroTerminated works', () {
    expect(splitZeroTerminated(Uint8List.fromList([])), <Uint8List>[]);
    expect(splitZeroTerminated(Uint8List.fromList([0])), <Uint8List>[
      Uint8List.fromList([]),
    ]);

    expect(splitZeroTerminated(Uint8List.fromList([1, 0, 1])), <Uint8List>[
      Uint8List.fromList([1]),
    ]);
    expect(
      splitZeroTerminated(Uint8List.fromList([2, 1, 0, 1, 0, 0])),
      <Uint8List>[
        Uint8List.fromList([2, 1]),
        Uint8List.fromList([1]),
        Uint8List.fromList([]),
      ],
    );
    expect(
      splitZeroTerminated(
        Uint8List.fromList([2, 1, 0, 1, 0, 2, 3, 0]),
        skipPrefix: 1,
      ),
      <Uint8List>[
        Uint8List.fromList([1]),
        Uint8List.fromList([]),
        Uint8List.fromList([3]),
      ],
    );
    expect(
      () => splitZeroTerminated(
        Uint8List.fromList([2, 1, 0, 1, 0, 0]),
        skipPrefix: 1,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('safe.bareRepository is enabled by default in test environment', () {
    // Regression protection for https://github.com/dart-lang/pub/issues/4770.
    final r = Process.runSync('git', [
      'config',
      '--get',
      'safe.bareRepository',
    ], environment: getPubTestEnvironment());
    expect(r.stdout, contains('explicit'));
    Process.runSync(
      'git',
      ['init', '--bare'],
      workingDirectory: sandbox,
      environment: getPubTestEnvironment(),
    );
    final r1 = Process.runSync(
      'git',
      ['log'],
      workingDirectory: sandbox,
      environment: getPubTestEnvironment(),
    );
    expect(r1.exitCode, isNot(0));
    expect(r1.stderr, contains('fatal: cannot use bare repository '));
  });
}
