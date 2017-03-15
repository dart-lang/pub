// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/utils.dart';
import 'package:scheduled_test/scheduled_test.dart' hide fail;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'descriptor.dart' as d;

/// The global [DescriptorServer] that's used by default.
///
/// `null` if there's no global server in use. This can be set to replace the
/// existing global server.
DescriptorServer get globalServer => _globalServer;
set globalServer(DescriptorServer value) {
  if (_globalServer == null) {
    currentSchedule.onComplete.schedule(() {
      _globalServer = null;
    }, 'clearing the global server');
  } else {
    _globalServer.close();
  }

  _globalServer = value;
}

DescriptorServer _globalServer;

/// Creates a global [DescriptorServer] to serve [contents] as static files.
///
/// This server will exist only for the duration of the pub run. It's accessible
/// via [server]. Subsequent calls to [serve] replace the previous server.
void serve([List<d.Descriptor> contents]) {
  globalServer = new DescriptorServer(contents);
}

/// Like [serve], but reports an error if a request ever comes in to the server.
void serveErrors() {
  globalServer = new DescriptorServer.errors();
}

class DescriptorServer {
  /// The server, or `null` before it's available.
  HttpServer _server;

  /// A future that will complete to the port used for the server.
  Future<int> get port => _portCompleter.future;
  final _portCompleter = new Completer<int>();

  /// Gets the list of paths that have been requested from the server.
  Future<List<String>> get requestedPaths =>
      schedule(() => _requestedPaths.toList(), "get previous network requests");

  /// The list of paths that have been requested from this server.
  final _requestedPaths = <String>[];

  /// Creates an HTTP server to serve [contents] as static files.
  ///
  /// This server exists only for the duration of the pub run. Subsequent calls
  /// to [serve] replace the previous server.
  DescriptorServer([List<d.Descriptor> contents]) {
    var baseDir = d.dir("serve-dir", contents);

    schedule(() async {
      _server = await shelf_io.serve((request) async {
        var path = p.posix.fromUri(request.url.path);
        _requestedPaths.add(path);

        try {
          var stream = await validateStream(baseDir.load(path));
          return new shelf.Response.ok(stream);
        } catch (_) {
          return new shelf.Response.notFound('File "$path" not found.');
        }
      }, 'localhost', 0);

      _portCompleter.complete(_server.port);
      _closeOnComplete();
    }, 'starting a server serving:\n${baseDir.describe()}');
  }

  /// Creates a server that reports an error if a request is ever received.
  DescriptorServer.errors() {
    schedule(() async {
      _server = await shelf_io.serve((request) {
        fail("The HTTP server received an unexpected request:\n"
            "${request.method} ${request.requestedUri}");
        return new shelf.Response.forbidden(null);
      }, 'localhost', 0);

      _portCompleter.complete(_server.port);
      _closeOnComplete();
    });
  }

  /// Schedules [requestedPaths] to be emptied.
  void clearRequestedPaths() {
    schedule(() {
      _requestedPaths.clear();
    }, "clearing requested paths");
  }

  /// Schedules the closing of this server.
  void close() {
    schedule(() async {
      if (_server == null) return;
      await _server.close();
    }, "closing DescriptorServer");
  }

  /// Schedules this server to close once the schedule is done.
  void _closeOnComplete() {
    currentSchedule.onComplete.schedule(() async {
      if (_server == null) return;
      await _server.close();
    }, "closing DescriptorServer");
  }
}
