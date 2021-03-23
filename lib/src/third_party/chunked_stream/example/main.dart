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

import 'dart:io' show stdout;
import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;
import 'package:chunked_stream/chunked_stream.dart';

void main() async {
  // Input consisting of: *([uint32 length] [blob of size length])
  // This is a series of blocks consisting of an uint32 length followed by
  // length number of bytes.
  //
  // Many format including tar, msgpack, protobuf, etc. have formats binary
  // encodings that consist of an integer indicating length of a blob of bytes.
  // ChunkedStreamIterator can be useful when decoding such formats.
  final inputStream = () async* {
    // Yield blob1 from stream
    final blob1 = utf8.encode('hello world');
    yield [blob1.length, 0, 0, 0]; // uint32 encoding of length
    yield blob1;

    // Yield blob2 from stream
    final blob2 = utf8.encode('small blob');
    yield [blob2.length, 0, 0, 0];
    yield blob2;
  }();

  // To ensure efficient reading, we buffer the stream upto 4096 bytes, for I/O
  // buffering can improve performance (in some cases).
  final bufferedStream = bufferChunkedStream(inputStream, bufferSize: 4096);

  // Create a chunk stream iterator over the buffered stream.
  final iterator = ChunkedStreamIterator(bufferedStream);

  while (true) {
    // Read the first 4 bytes
    final lengthBytes = await iterator.read(4);

    // We have EOF if there is no more bytes
    if (lengthBytes.isEmpty) {
      break;
    }

    // Read those 4 bytes as Uint32
    final length = Uint8List.fromList(lengthBytes).buffer.asUint32List()[0];

    // Read the next [length] bytes, and write them to stdout
    print('Blob of $length bytes:');
    await stdout.addStream(iterator.substream(length));
    print('\n');
  }
}
