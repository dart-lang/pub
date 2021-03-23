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

import 'package:meta/meta.dart' show sealed;
import 'package:chunked_stream/src/read_chunked_stream.dart';

/// Auxiliary class for iterating over the items in a chunked stream.
///
/// A _chunked stream_ is a stream in which items arrives in chunks with each
/// event from the stream. A common example is a byte stream with the type
/// `Stream<List<int>>`. In such a byte stream bytes arrives in chunks
/// `List<int>` for each event.
///
/// Note. methods on this class may not be called concurrently.
@sealed
abstract class ChunkedStreamIterator<T> {
  factory ChunkedStreamIterator(Stream<List<T>> stream) {
    return _ChunkedStreamIterator<T>(stream);
  }

  /// Returns a list of the next [size] elements.
  ///
  /// Returns a list with less than [size] elements if the end of stream is
  /// encountered before [size] elements are read.
  ///
  /// If an error is encountered before reading [size] elements, the error
  /// will be thrown.
  Future<List<T>> read(int size);

  /// Cancels the stream iterator (and the underlying stream subscription)
  /// early.
  ///
  /// Users should call [cancel] to ensure that the stream is properly closed
  /// if they need to stop listening earlier than the end of the stream.
  Future<void> cancel();

  /// Returns a sub-[Stream] with the next [size] elements.
  ///
  /// A sub-[Stream] is a [Stream] consisting of the next [size] elements
  /// in the same order they occur in the stream used to create this iterator.
  ///
  /// If [read] is called before the sub-[Stream] is fully read, a [StateError]
  /// will be thrown.
  ///
  /// ```dart
  /// final s = ChunkedStreamIterator(_chunkedStream([
  ///   ['a', 'b', 'c'],
  ///   ['1', '2'],
  /// ]));
  /// expect(await s.read(1), equals(['a']));
  ///
  /// // creates a substream from the chunks holding the
  /// // next three elements (['b', 'c'], ['1'])
  /// final i = StreamIterator(s.substream(3));
  /// expect(await i.moveNext(), isTrue);
  /// expect(await i.current, equals(['b', 'c']));
  /// expect(await i.moveNext(), isTrue);
  /// expect(await i.current, equals(['1']));
  ///
  /// // Since the substream has been read till the end, we can continue reading
  /// // from the initial stream.
  /// expect(await s.read(1), equals(['2']));
  /// ```
  ///
  /// The resulting stream may contain less than [size] elements if the
  /// underlying stream has less than [size] elements before the end of stream.
  ///
  /// When the substream is cancelled, the remaining elements in the substream
  /// are drained.
  Stream<List<T>> substream(int size);
}

/// General purpose _chunked stream iterator_.
class _ChunkedStreamIterator<T> implements ChunkedStreamIterator<T> {
  /// Underlying iterator that iterates through the original stream.
  final StreamIterator<List<T>> _iterator;

  /// Keeps track of the number of elements left in the current substream.
  int _toRead = 0;

  /// Buffered items from a previous chunk. Items in this list should not have
  /// been read by the user.
  late List<T> _buffered;

  /// Instance variable representing an empty list object, used as the empty
  /// default state for [_buffered]. Take caution not to write code that
  /// directly modify the [_buffered] list by adding elements to it.
  final List<T> _emptyList = [];

  _ChunkedStreamIterator(Stream<List<T>> stream)
      : _iterator = StreamIterator(stream) {
    _buffered = _emptyList;
  }

  /// Returns a list of the next [size] elements.
  ///
  /// Returns a list with less than [size] elements if the end of stream is
  /// encounted before [size] elements are read.
  ///
  /// If an error is encountered before reading [size] elements, the error
  /// will be thrown.
  @override
  Future<List<T>> read(int size) async =>
      await readChunkedStream(substream(size));

  /// Cancels the stream iterator (and the underlying stream subscription)
  /// early.
  ///
  /// Users should call [cancel] to ensure that the stream is properly closed
  /// if they need to stop listening earlier than the end of the stream.
  @override
  Future<void> cancel() async => await _iterator.cancel();

  /// Returns a sub-[Stream] with the next [size] elements.
  ///
  /// A sub-[Stream] is a [Stream] consisting of the next [size] elements
  /// in the same order they occur in the stream used to create this iterator.
  ///
  /// If [read] is called before the sub-[Stream] is fully read, a [StateError]
  /// will be thrown.
  ///
  /// ```dart
  /// final s = ChunkedStreamIterator(_chunkedStream([
  ///   ['a', 'b', 'c'],
  ///   ['1', '2'],
  /// ]));
  /// expect(await s.read(1), equals(['a']));
  ///
  /// // creates a substream from the chunks holding the
  /// // next three elements (['b', 'c'], ['1'])
  /// final i = StreamIterator(s.substream(3));
  /// expect(await i.moveNext(), isTrue);
  /// expect(await i.current, equals(['b', 'c']));
  /// expect(await i.moveNext(), isTrue);
  /// expect(await i.current, equals(['1']));
  ///
  /// // Since the substream has been read till the end, we can continue reading
  /// // from the initial stream.
  /// expect(await s.read(1), equals(['2']));
  /// ```
  ///
  /// The resulting stream may contain less than [size] elements if the
  /// underlying stream has less than [size] elements before the end of stream.
  ///
  /// When the substream is cancelled, the remaining elements in the substream
  /// are drained.
  @override
  Stream<List<T>> substream(int size) {
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'must be non-negative');
    }
    if (_toRead > 0) {
      throw StateError('Concurrent invocations are not supported!');
    }

    _toRead = size;

    // Creates a new [StreamController] made out of the elements from
    // [_iterator].
    final substream = _substream();
    final newController = StreamController<List<T>>();

    // When [newController]'s stream is cancelled, drain all the remaining
    // elements.
    newController.onCancel = () async {
      await _substream().drain();
    };

    // Since the controller should only have [size] elements, we close
    // [newController]'s stream once all the elements in [substream] have
    // been added. This is necessary so that await-for loops on
    // [newController.stream] will complete.
    final future = newController.addStream(substream);
    future.whenComplete(() {
      newController.close();
    });

    return newController.stream;
  }

  /// Asynchronous generator implementation for [substream].
  Stream<List<T>> _substream() async* {
    // Only yield when there are elements to be read.
    while (_toRead > 0) {
      // If [_buffered] is empty, set it to the next element in the stream if
      // possible.
      if (_buffered.isEmpty) {
        if (!(await _iterator.moveNext())) {
          break;
        }

        _buffered = _iterator.current;
      }

      List<T> toYield;
      if (_toRead < _buffered.length) {
        // If there are less than [_buffered.length] elements left to be read
        // in the substream, sublist the chunk from [_buffered] accordingly.
        toYield = _buffered.sublist(0, _toRead);
        _buffered = _buffered.sublist(_toRead);
        _toRead = 0;
      } else {
        // Otherwise prepare to yield the full [_buffered] chunk, updating
        // the other variables accordingly
        toYield = _buffered;
        _toRead -= _buffered.length;
        _buffered = _emptyList;
      }

      yield toYield;
    }

    // Set [_toRead] to be 0. This line is necessary if the size that is passed
    // in is greater than the number of elements in [_iterator].
    _toRead = 0;
  }
}

/// Extension methods for [ChunkedStreamIterator] when working with byte-streams
/// [Stream<List<int>>].
extension ChunkedStreamIteratorByteStreamExt on ChunkedStreamIterator<int> {
  /// Read bytes as [Uint8List].
  ///
  /// This does the same as [read], except it uses [readByteStream] to create
  /// a [Uint8List], which offers better performance.
  Future<Uint8List> readBytes(int size) async =>
      await readByteStream(substream(size));
}
