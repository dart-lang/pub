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
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:chunked_stream/chunked_stream.dart';

Stream<List<T>> _chunkedStream<T>(List<List<T>> chunks) async* {
  for (final chunk in chunks) {
    yield chunk;
  }
}

Stream<List<T>> _chunkedStreamWithError<T>(List<List<T>> chunks) async* {
  for (final chunk in chunks) {
    yield chunk;
  }

  throw StateError('test generated error');
}

void main() {
  test('read() -- chunk in given size', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(3), equals(['a', 'b', 'c']));
    expect(await s.read(2), equals(['1', '2']));
    expect(await s.read(1), equals([]));
  });

  test('read() propagates stream error', () async {
    final s = ChunkedStreamIterator(_chunkedStreamWithError([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(3), equals(['a', 'b', 'c']));
    expect(() async => await s.read(3), throwsStateError);
  });

  test('read() -- chunk in given size', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(2), equals(['a', 'b']));
    expect(await s.read(3), equals(['c', '1', '2']));
    expect(await s.read(1), equals([]));
  });

  test('read() -- chunks one item at the time', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));
    expect(await s.read(1), equals(['b']));
    expect(await s.read(1), equals(['c']));
    expect(await s.read(1), equals(['1']));
    expect(await s.read(1), equals(['2']));
    expect(await s.read(1), equals([]));
  });

  test('read() -- one big chunk', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(6), equals(['a', 'b', 'c', '1', '2']));
  });

  test('substream() propagates stream error', () async {
    final s = ChunkedStreamIterator(_chunkedStreamWithError([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(3), equals(['a', 'b', 'c']));
    final substream = s.substream(3);
    final subChunkedStreamIterator = ChunkedStreamIterator(substream);
    expect(
        () async => await subChunkedStreamIterator.read(3), throwsStateError);
  });

  test('substream() + readChunkedStream()', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await readChunkedStream(s.substream(5)),
        equals(['a', 'b', 'c', '1', '2']));
    expect(await s.read(1), equals([]));
  });

  test('(substream() + readChunkedStream()) x 2', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await readChunkedStream(s.substream(2)), equals(['a', 'b']));
    expect(await readChunkedStream(s.substream(3)), equals(['c', '1', '2']));
  });

  test('substream() + readChunkedStream() -- past end', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await readChunkedStream(s.substream(6)),
        equals(['a', 'b', 'c', '1', '2']));
    expect(await s.read(1), equals([]));
  });

  test('read() substream() + readChunkedStream() read()', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));
    expect(await readChunkedStream(s.substream(3)), equals(['b', 'c', '1']));
    expect(await s.read(2), equals(['2']));
  });

  test(
      'read() StreamIterator(substream()).cancel() read() '
      '-- one item at the time', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));
    final i = StreamIterator(s.substream(3));
    expect(await i.moveNext(), isTrue);
    await i.cancel();
    expect(await s.read(1), equals(['2']));
    expect(await s.read(1), equals([]));
  });

  test(
      'read() StreamIterator(substream()) read() '
      '-- one item at the time', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));
    final i = StreamIterator(s.substream(3));
    expect(await i.moveNext(), isTrue);
    expect(await i.current, equals(['b', 'c']));
    expect(await i.moveNext(), isTrue);
    expect(await i.current, equals(['1']));
    expect(await i.moveNext(), isFalse);
    expect(await s.read(1), equals(['2']));
    expect(await s.read(1), equals([]));
  });

  test('substream() x 2', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(
        await s.substream(2).toList(),
        equals([
          ['a', 'b']
        ]));
    expect(
        await s.substream(3).toList(),
        equals([
          ['c'],
          ['1', '2']
        ]));
  });

  test(
      'read() StreamIterator(substream()).cancel() read() -- '
      'cancellation after reading', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));
    final i = StreamIterator(s.substream(3));
    expect(await i.moveNext(), isTrue);
    await i.cancel();
    expect(await s.read(1), equals(['2']));
    expect(await s.read(1), equals([]));
  });

  test(
      'read() StreamIterator(substream()).cancel() read() -- '
      'cancellation after reading (2)', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2', '3'],
      ['4', '5', '6']
    ]));
    expect(await s.read(1), equals(['a']));
    final i = StreamIterator(s.substream(6));
    expect(await i.moveNext(), isTrue);
    await i.cancel();
    expect(await s.read(1), equals(['5']));
    expect(await s.read(1), equals(['6']));
  });

  // The following test fails because before the first `moveNext` is called,
  // the [StreamIterator] is not intialized to the correct
  // [StreamSubscription], thus calling `cancel` does not correctly cancel the
  // underlying stream, resulting in an error.
  //
  // test(
  //     'read() substream().cancel() read() -- '
  //     'cancellation without reading', () async {
  //   final s = ChunkedStreamIterator(_chunkedStream([
  //     ['a', 'b', 'c'],
  //     ['1', '2'],
  //   ]));
  //   expect(await s.read(1), equals(['a']));
  //   final i = StreamIterator(s.substream(3));
  //   await i.cancel();
  //   expect(await s.read(1), equals(['1']));
  //   expect(await s.read(1), equals(['2']));
  // });

  test(
      'read() StreamIterator(substream()) read() -- '
      'not cancelling produces StateError', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));
    final i = StreamIterator(s.substream(3));
    expect(await i.moveNext(), isTrue);
    expect(() async => await s.read(1), throwsStateError);
  });

  test(
      'read() StreamIterator(substream()) read() -- '
      'not cancelling produces StateError (2)', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));

    /// ignore: unused_local_variable
    final i = StreamIterator(s.substream(3));
    expect(() async => await s.read(1), throwsStateError);
  });

  test(
      'read() substream() that ends with first chunk + '
      'readChunkedStream() read()', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));
    expect(
        await s.substream(2).toList(),
        equals([
          ['b', 'c']
        ]));
    expect(await s.read(3), equals(['1', '2']));
  });

  test(
      'read() substream() that ends with first chunk + drain() '
      'read()', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.read(1), equals(['a']));
    final sub = s.substream(2);
    await sub.drain();
    expect(await s.read(3), equals(['1', '2']));
  });

  test(
      'read() substream() that ends with second chunk + '
      'readChunkedStream() read()', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
      ['3', '4']
    ]));
    expect(await s.read(1), equals(['a']));
    expect(
        await s.substream(4).toList(),
        equals([
          ['b', 'c'],
          ['1', '2']
        ]));
    expect(await s.read(3), equals(['3', '4']));
  });

  test(
      'read() substream() that ends with second chunk + '
      'drain() read()', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
      ['3', '4'],
    ]));
    expect(await s.read(1), equals(['a']));
    final substream = s.substream(4);
    await substream.drain();
    expect(await s.read(3), equals(['3', '4']));
  });

  test(
      'read() substream() read() before '
      'draining substream produces StateError', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
      ['3', '4'],
    ]));
    expect(await s.read(1), equals(['a']));
    // ignore: unused_local_variable
    final substream = s.substream(4);
    expect(() async => await s.read(3), throwsStateError);
  });

  test('creating two substreams simultaneously causes a StateError', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
      ['3', '4'],
    ]));
    expect(await s.read(1), equals(['a']));
    // ignore: unused_local_variable
    final substream = s.substream(4);
    expect(() async {
      //ignore: unused_local_variable
      final substream2 = s.substream(3);
    }, throwsStateError);
  });

  test('nested ChunkedStreamIterator', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      ['a', 'b'],
      ['1', '2'],
      ['3', '4'],
    ]));
    expect(await s.read(1), equals(['a']));
    final substream = s.substream(4);
    final nested = ChunkedStreamIterator(substream);
    expect(await nested.read(2), equals(['b', '1']));
    expect(await nested.read(3), equals(['2', '3']));
    expect(await nested.read(2), equals([]));
    expect(await s.read(1), equals(['4']));
  });

  test('ByteStreamIterator', () async {
    final s = ChunkedStreamIterator(_chunkedStream([
      [1, 2, 3],
      [4],
    ]));
    expect(await s.readBytes(1), equals([1]));
    expect(await s.readBytes(1), isA<Uint8List>());
    expect(await s.readBytes(1), equals([3]));
    expect(await s.readBytes(1), equals([4]));
    expect(await s.readBytes(1), equals([]));
  });
}
