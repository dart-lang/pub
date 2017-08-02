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
  shelf.Server _server;

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
      new DescriptorServer._(
          await shelf_io.IOServer.bind('localhost', 0), contents);

  /// Creates a server that reports an error if a request is ever received.
  static Future<DescriptorServer> errors() async =>
      new DescriptorServer._errors(
          await shelf_io.IOServer.bind('localhost', 0));

  DescriptorServer._(this._server, Iterable<d.Descriptor> contents)
      : _baseDir = d.dir("serve-dir", contents) {
    _server.mount((request) async {
      var path = p.posix.fromUri(request.url.path);
      requestedPaths.add(path);

      try {
        var stream = await validateStream(_baseDir.load(path));
        return new shelf.Response.ok(stream);
      } catch (_) {
        return new shelf.Response.notFound('File "$path" not found.');
      }
    });
    addTearDown(() => _server.close());
  }

  DescriptorServer._errors(this._server) : _baseDir = d.dir("serve-dir", []) {
    _server.mount((request) {
      fail("The HTTP server received an unexpected request:\n"
          "${request.method} ${request.requestedUri}");
      return new shelf.Response.forbidden(null);
    });
    addTearDown(() => _server.close());
  }

  /// Closes this server.
  Future close() => _server.close();
}
