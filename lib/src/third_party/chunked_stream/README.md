Chunked Stream Utilities
========================
Utilities for working with chunked streams, such as `Stream<List<int>>`.

**Disclaimer:** This is not an officially supported Google product.

A _chunked stream_ is a stream where the data arrives in chunks. The most
common example is a byte stream, which conventionally has the type
`Stream<List<int>>`. We say a byte stream in chunked because bytes arrives in
chunks, rather than individiually.

A byte stream could technically have the type `Stream<int>`, however, this would
be very inefficient, as each byte would be passed as an individual event.
Instead bytes arrives in chunks (`List<int>`) and the type of a byte stream
is `Stream<List<int>>`.

For easily converting a byte stream `Stream<List<int>>` into a single byte
buffer `Uint8List` (which implements `List<int>`) this package provides
`readByteStream(stream, maxSize: 1024*1024)`, which conveniently takes an
optional `maxSize` parameter to help avoid running out of memory.

**Example**
```dart
import 'dart:io';
import 'dart:convert';
import 'package:chunked_stream/chunked_stream.dart';

Future<void> main() async {
  // Open README.md as a byte stream
  Stream<List<int>> fileStream = File('README.md').openRead();

  // Read all bytes from the stream
  final Uint8List bytes = await readByteStream(fileStream);
  
  // Convert content to string using utf8 codec from dart:convert and print
  print(utf8.decode(bytes));
}
```

To make it easy to process chunked streams, such as `Stream<List<int>>`,
this package provides `ChunkedStreamIterator` which allows you to specify how
many elements you want, and buffer unconsumed elements, making it easy to work
with chunked streams one element at the time.

**Example**
```dart
final reader = ChunkedStreamIterator(File('my-file.txt').openRead());
// While the reader has a next byte
while (true) {
  var data = await reader.read(1);  // read one byte
  if (data.length < 0) {
    print('End of file reached');
    break;
  }
  print('next byte: ${data[0]}');
}
```
