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

import 'package:test/test.dart';
import 'package:chunked_stream/chunked_stream.dart';

void main() {
  for (var i = 1; i < 6; i++) {
    test('bufferChunkedStream (bufferSize: $i)', () async {
      final s = (() async* {
        yield ['a'];
        yield ['b'];
        yield ['c'];
      })();

      final bs = bufferChunkedStream(s, bufferSize: i);
      final result = await readChunkedStream(bs);
      expect(result, equals(['a', 'b', 'c']));
    });
  }
}
