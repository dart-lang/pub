// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart' hide fail;

import 'package:pub/src/utils.dart';

import 'descriptor.dart' as d;

/// The global [DescriptorServer] that's used by default.
///
/// `null` if there's no global server in use. This can be set to replace the
/// existing global server.
DescriptorServer get globalServer => _globalServer;
set globalServer(DescriptorServer value) {
  if (_globalServer == null) {
    addTearDown(() {
      _globalServer = null;
    });
  } else {
    expect(_globalServer.close(), completes);
  }

  _globalServer = value;
}

DescriptorServer _globalServer;

/// Creates a global [DescriptorServer] to serve [contents] as static files.
///
/// This server will exist only for the duration of the pub run. It's accessible
/// via [server]. Subsequent calls to [serve] replace the previous server.
Future serve([List<d.Descriptor> contents]) async {
  globalServer = await DescriptorServer.start(contents);
}

/// Like [serve], but reports an error if a request ever comes in to the server.
Future serveErrors() async {
  globalServer = await DescriptorServer.errors();
}

class DescriptorServer {
  /// The underlying server.
  final shelf.Server _server;

  /// A future that will complete to the port used for the server.
  int get port => _server.url.port;

  /// The list of paths that have been requested from this server.
  final requestedPaths = <String>[];

  /// The base directory descriptor of the directories served by [this].
  final d.DirectoryDescriptor _baseDir;

  /// The descriptors served by this server.
  ///
  /// This can safely be modified between requests.
  List<d.Descriptor> get contents => _baseDir.contents;

  /// Creates an HTTP server to serve [contents] as static files.
  ///
  /// This server exists only for the duration of the pub run. Subsequent calls
  /// to [serve] replace the previous server.
  static Future<DescriptorServer> start([List<d.Descriptor> contents]) async =>
      DescriptorServer._(
          await shelf_io.IOServer.bind('localhost', 0), contents);

  /// Creates a server that reports an error if a request is ever received.
  static Future<DescriptorServer> errors() async =>
      DescriptorServer._errors(await shelf_io.IOServer.bind('localhost', 0));

  DescriptorServer._(this._server, Iterable<d.Descriptor> contents)
      : _baseDir = d.dir('serve-dir', contents) {
    _server.mount((request) async {
      var path = p.posix.fromUri(request.url.path);
      requestedPaths.add(path);

      try {
        var stream = await _validateStream(_baseDir.load(path));
        return shelf.Response.ok(stream);
      } catch (_) {
        return shelf.Response.notFound('File "$path" not found.');
      }
    });
    addTearDown(_server.close);
  }

  DescriptorServer._errors(this._server) : _baseDir = d.dir('serve-dir', []) {
    _server.mount((request) {
      fail('The HTTP server received an unexpected request:\n'
          '${request.method} ${request.requestedUri}');
    });
    addTearDown(_server.close);
  }

  /// Closes this server.
  Future close() => _server.close();
}

/// Ensures that [stream] can emit at least one value successfully (or close
/// without any values).
///
/// For example, reading asynchronously from a non-existent file will return a
/// stream that fails on the first chunk. In order to handle that more
/// gracefully, you may want to check that the stream looks like it's working
/// before you pipe the stream to something else.
///
/// This lets you do that. It returns a [Future] that completes to a [Stream]
/// emitting the same values and errors as [stream], but only if at least one
/// value can be read successfully. If an error occurs before any values are
/// emitted, the returned Future completes to that error.
Future<Stream<T>> _validateStream<T>(Stream<T> stream) {
  var completer = Completer<Stream<T>>();
  var controller = StreamController<T>(sync: true);

  StreamSubscription subscription;
  subscription = stream.listen((value) {
    // We got a value, so the stream is valid.
    if (!completer.isCompleted) completer.complete(controller.stream);
    controller.add(value);
  }, onError: (error, [StackTrace stackTrace]) {
    // If the error came after values, it's OK.
    if (completer.isCompleted) {
      controller.addError(error, stackTrace);
      return;
    }

    // Otherwise, the error came first and the stream is invalid.
    completer.completeError(error, stackTrace);

    // We won't be returning the stream at all in this case, so unsubscribe
    // and swallow the error.
    subscription.cancel();
  }, onDone: () {
    // It closed with no errors, so the stream is valid.
    if (!completer.isCompleted) completer.complete(controller.stream);
    controller.close();
  });

  return completer.future;
}
