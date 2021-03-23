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

import 'dart:async';

/// Buffer an chunked stream.
///
/// This reads [input] into an internal buffer of size [bufferSize] elements.
/// When the internal buffer is full the [input] stream is _paused_, as elements
/// are consumed from the stream returned the [input] stream in _resumed_.
///
/// If reading from a chunked stream as it arrives from disk or network it can
/// be useful to buffer the stream internally to avoid blocking disk or network
/// reads while waiting for CPU to process the bytes read.
Stream<List<T>> bufferChunkedStream<T>(
  Stream<List<T>> input, {
  int bufferSize = 16 * 1024,
}) async* {
  if (bufferSize <= 0) {
    throw ArgumentError.value(
        bufferSize, 'bufferSize', 'bufferSize must be positive');
  }

  late final StreamController<List<T>> c;
  StreamSubscription? sub;

  c = StreamController(
    onListen: () {
      sub = input.listen((chunk) {
        bufferSize -= chunk.length;
        c.add(chunk);

        final currentSub = sub;
        if (bufferSize <= 0 && currentSub != null && !currentSub.isPaused) {
          currentSub.pause();
        }
      }, onDone: () {
        c.close();
      }, onError: (e, st) {
        c.addError(e, st);
      });
    },
    onCancel: () => sub!.cancel(),
  );

  await for (final chunk in c.stream) {
    yield chunk;
    bufferSize += chunk.length;

    final currentSub = sub;
    if (bufferSize > 0 && currentSub != null && currentSub.isPaused) {
      currentSub.resume();
    }
  }
}
