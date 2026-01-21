// gzip_js.dart
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Exposes the native browser DecompressionStream wrapped as a Dart Converter.
final Converter<List<int>, List<int>> gzipDecoder = _WebGzipDecoder();

/// A local definition for the underlying source object.
/// Required because 'web.UnderlyingSource' was removed in package:web 2.0.
extension type _GzipSource._(JSObject _) implements JSObject {
  external factory _GzipSource({JSFunction pull, JSFunction cancel});
}

class _WebGzipDecoder extends Converter<List<int>, List<int>> {
  @override
  List<int> convert(List<int> input) {
    throw UnsupportedError(
      'GZIP on the web is asynchronous. Use .bind() or .transform() instead of .convert().',
    );
  }

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) async* {
    final readable = _dartStreamToReadableStream(stream);
    final decompressor = web.DecompressionStream('gzip');

    // Pipe the stream through the decompressor.
    // Cast to ReadableWritablePair to satisfy strict type checks.
    final decompressed = readable.pipeThrough(
      decompressor as web.ReadableWritablePair,
    );

    // Get the reader and cast to the default reader type.
    final reader = decompressed.getReader() as web.ReadableStreamDefaultReader;

    try {
      while (true) {
        // await the promise.
        final chunk = await reader.read().toDart;

        if (chunk.done) break;

        final value = chunk.value;
        if (value != null) {
          // Cast value to JSUint8Array before converting to Dart.
          yield (value as JSUint8Array).toDart;
        }
      }
    } finally {
      reader.releaseLock();
    }
  }

  web.ReadableStream _dartStreamToReadableStream(Stream<List<int>> stream) {
    final iterator = StreamIterator(stream);

    final source = _GzipSource(
      // FIX: The callback must return a JSPromise, not a Future.
      pull:
          ((web.ReadableStreamDefaultController controller) {
            return Future(() async {
              if (await iterator.moveNext()) {
                final chunk = Uint8List.fromList(iterator.current);
                controller.enqueue(chunk.toJS);
              } else {
                controller.close();
              }
            }).toJS; // <--- Converts Future<void> to JSPromise
          }).toJS,

      // FIX: Return a JSPromise here as well.
      cancel:
          ((JSAny? reason) {
            return iterator.cancel().toJS;
          }).toJS,
    );

    return web.ReadableStream(source as JSObject);
  }
}
