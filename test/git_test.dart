// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:pub/src/git.dart';
import 'package:test/test.dart';

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
}
