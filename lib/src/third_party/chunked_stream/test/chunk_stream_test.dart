// Copyright 2020 Google LLC
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

import 'package:test/test.dart';
import 'package:chunked_stream/chunked_stream.dart';

void main() {
  for (var N = 1; N < 6; N++) {
    test('asChunkedStream (N = $N) preserves elements', () async {
      final s = (() async* {
        for (var j = 0; j < 97; j++) {
          yield j;
        }
      })();

      final result = await readChunkedStream(asChunkedStream(N, s));
      expect(result, hasLength(97));
      expect(result, equals(List.generate(97, (j) => j)));
    });

    test('asChunkedStream (N = $N) has chunk size N', () async {
      final s = (() async* {
        for (var j = 0; j < 97; j++) {
          yield j;
        }
      })();

      final chunks = await asChunkedStream(N, s).toList();

      // Last chunk may be smaller than N
      expect(chunks.removeLast(), hasLength(lessThanOrEqualTo(N)));
      // Last chunk must be N
      expect(chunks, everyElement(hasLength(N)));
    });
  }
}
