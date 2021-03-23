// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// @dart = 2.12

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:chunked_stream/chunked_stream.dart';

void main() {
  test('readChunkedStream', () async {
    final s = (() async* {
      yield ['a'];
      yield ['b'];
      yield ['c'];
    })();
    expect(await readChunkedStream(s), equals(['a', 'b', 'c']));
  });

  test('readByteStream', () async {
    final s = (() async* {
      yield [1, 2];
      yield Uint8List.fromList([3]);
      yield [4];
    })();
    final result = await readByteStream(s);
    expect(result, equals([1, 2, 3, 4]));
    expect(result, isA<Uint8List>());
  });
}
