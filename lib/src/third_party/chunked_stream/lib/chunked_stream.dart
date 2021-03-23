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

/// Utilities for working with chunked streams.
///
/// This library provides the following utilities:
///  * [ChunkedStreamIterator], for reading a chunked stream by iterating over
///  chunks and splitting into substreams.
///  * [readByteStream], for reading a byte stream into a single [Uint8List].
///  Often useful for converting [Stream<List<int>>] to [Uint8List].
///  * [readChunkedStream], for reading a chunked stream into a single big list.
///  * [limitChunkedStream], for wrapping a chunked stream as a new stream with
///  length limit, useful when accepting input streams from untrusted network.
///  * [bufferChunkedStream], for buffering a chunked stream. This can be useful
///  to improve I/O performance if reading the stream chunk by chunk with
///  frequent pause/resume calls, as is the case when using
///  [ChunkedStreamIterator].
///  * [asChunkedStream], for wrapping a [Stream<T>] as [Stream<List<T>>],
///  useful for batch processing elements from a stream.
library chunked_stream;

import 'dart:typed_data';

import 'src/chunk_stream.dart';
import 'src/chunked_stream_buffer.dart';
import 'src/chunked_stream_iterator.dart';
import 'src/read_chunked_stream.dart';

export 'src/chunk_stream.dart';
export 'src/chunked_stream_buffer.dart';
export 'src/chunked_stream_iterator.dart';
export 'src/read_chunked_stream.dart';
