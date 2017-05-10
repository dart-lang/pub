// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:barback/barback.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:stack_trace/stack_trace.dart';

import '../barback.dart';
import '../io.dart';
import '../log.dart' as log;
import '../utils.dart';
import 'base_server.dart';
import 'asset_environment.dart';

import 'dartdevc/dartdevc_environment.dart';

/// Callback for determining if an asset with [id] should be served or not.
typedef bool AllowAsset(AssetId id);

/// A server that serves assets transformed by barback.
class BarbackServer extends BaseServer<BarbackServerResult> {
  /// The package whose assets are being served.
  final String package;

  /// The directory in the root which will serve as the root of this server as
  /// a native platform path.
  ///
  /// This may be `null` in which case no files in the root package can be
  /// served and only assets in "lib" directories are available.
  final String rootDirectory;

  /// Optional callback to determine if an asset should be served.
  ///
  /// This can be set to allow outside code to filter out assets. Pub serve
  /// uses this after plug-ins are loaded to avoid serving ".dart" files in
  /// release mode.
  ///
  /// If this is `null`, all assets may be served.
  AllowAsset allowAsset;

  final DartDevcEnvironment dartDevcEnvironment;

  /// Creates a new server and binds it to [port] of [host].
  ///
  /// This server serves assets from [barback], and uses [rootDirectory]
  /// (which is relative to the root directory of [package]) as the root
  /// directory. If [rootDirectory] is omitted, the bound server can only be
  /// used to serve assets from packages' lib directories (i.e. "packages/..."
  /// URLs). If [package] is omitted, it defaults to the entrypoint package.
  static Future<BarbackServer> bind(
      AssetEnvironment environment, String host, int port,
      {String package,
      String rootDirectory,
      DartDevcEnvironment dartDevcEnvironment}) {
    if (package == null) package = environment.rootPackage.name;
    return bindServer(host, port).then((server) {
      if (rootDirectory == null) {
        log.fine('Serving packages on $host:$port.');
      } else {
        log.fine('Bound "$rootDirectory" to $host:$port.');
      }
      return new BarbackServer._(environment, server, package, rootDirectory,
          dartDevcEnvironment: dartDevcEnvironment);
    });
  }

  BarbackServer._(AssetEnvironment environment, HttpServer server, this.package,
      this.rootDirectory,
      {this.dartDevcEnvironment})
      : super(environment, server);

  /// Converts a [url] served by this server into an [AssetId] that can be
  /// requested from barback.
  AssetId urlToId(Uri url) {
    // See if it's a URL to a public directory in a dependency.
    var id = packagesUrlToId(url);
    if (id != null) return id;

    if (rootDirectory == null) {
      throw new FormatException(
          "This server cannot serve out of the root directory. Got $url.");
    }

    // Otherwise, it's a path in current package's [rootDirectory].
    var parts = path.url.split(url.path);

    // Strip the leading "/" from the URL.
    if (parts.isNotEmpty && parts.first == "/") parts = parts.skip(1);

    var relativePath = path.url.join(rootDirectory, path.url.joinAll(parts));
    return new AssetId(package, relativePath);
  }

  /// Handles an HTTP request.
  Future<shelf.Response> handleRequest(shelf.Request request) async {
    if (request.method != "GET" && request.method != "HEAD") {
      return methodNotAllowed(request);
    }

    var id;
    try {
      id = urlToId(request.url);
    } on FormatException catch (ex) {
      // If we got here, we had a path like "/packages" which is a special
      // directory, but not a valid path since it lacks a following package
      // name.
      return notFound(request, error: ex.message);
    }

    // See if the asset should be blocked.
    if (allowAsset != null && !allowAsset(id)) {
      return notFound(request,
          error: "Asset $id is not available in this configuration.",
          asset: id);
    }

    return environment.barback
        .getAssetById(id)
        .then((asset) => _serveAsset(request, asset))
        .catchError((error, trace) {
      if (error is! AssetNotFoundException) throw error;
      return environment.barback
          .getAssetById(id.addExtension("/index.html"))
          .then((asset) {
        if (request.url.path.isEmpty || request.url.path.endsWith('/')) {
          return _serveAsset(request, asset);
        }

        // We only want to serve index.html if the URL explicitly ends in a
        // slash. For other URLs, we redirect to one with the slash added to
        // implicitly support that too. This follows Apache's behavior.
        logRequest(request, "302 Redirect to /${request.url}/");
        return new shelf.Response.found('/${request.url}/');
      }).catchError((newError, newTrace) {
        // If we find neither the original file or the index, we should report
        // the error about the original to the user.
        throw newError is AssetNotFoundException ? error : newError;
      });
    }).catchError((error, trace) {
      if (error is! AssetNotFoundException || dartDevcEnvironment == null) {
        throw error;
      }
      return dartDevcEnvironment
          .getAssetById(id)
          .then((asset) => _serveAsset(request, asset));
    }).catchError((error, trace) {
      if (error is! AssetNotFoundException) {
        var chain = new Chain.forTrace(trace);
        logRequest(request, "$error\n$chain");

        addError(error, chain);
        close();
        return new shelf.Response.internalServerError();
      }

      addResult(new BarbackServerResult._failure(request.url, id, error));
      return notFound(request, asset: id);
    }).then((response) {
      // Allow requests of any origin to access "pub serve". This is useful for
      // running "pub serve" in parallel with another development server. Since
      // "pub serve" is only used as a development server and doesn't require
      // any sort of credentials anyway, this is secure.
      return response
          .change(headers: const {"Access-Control-Allow-Origin": "*"});
    });
  }

  /// Returns the body of [asset] as a response to [request].
  Future<shelf.Response> _serveAsset(shelf.Request request, Asset asset) async {
    try {
      var streams =
          StreamSplitter.splitFrom(await validateStream(asset.read()));
      var responseStream = streams.first;
      var hashStream = streams.last;

      // Allow the asset to be cached based on its content hash.
      var assetSha = await sha1Stream(hashStream);
      var previousSha = request.headers["if-none-match"];

      var headers = {
        // Enable browser caching of the asset.
        "ETag": assetSha
      };

      if (assetSha == previousSha) {
        // We're requesting an unchanged asset so don't push its body down the
        // wire again.
        addResult(new BarbackServerResult._cached(request.url, asset.id));
        return new shelf.Response.notModified(headers: headers);
      } else {
        addResult(new BarbackServerResult._success(request.url, asset.id));
        var mimeType = lookupMimeType(asset.id.path);
        if (mimeType != null) headers['Content-Type'] = mimeType;
        return new shelf.Response.ok(responseStream, headers: headers);
      }
    } catch (error, trace) {
      addResult(new BarbackServerResult._failure(request.url, asset.id, error));

      // If we couldn't read the asset, handle the error gracefully.
      if (error is FileSystemException) {
        // Assume this means the asset was a file-backed source asset
        // and we couldn't read it, so treat it like a missing asset.
        return notFound(request, error: error.toString(), asset: asset.id);
      }

      var chain = new Chain.forTrace(trace);
      logRequest(request, "$error\n$chain");

      // Otherwise, it's some internal error.
      return new shelf.Response.internalServerError(body: error.toString());
    }
  }
}

/// The result of the server handling a URL.
///
/// Only requests for which an asset was requested from barback will emit a
/// result. Malformed requests will be handled internally.
class BarbackServerResult {
  /// The requested url.
  final Uri url;

  /// The id that [url] identifies.
  final AssetId id;

  /// The error thrown by barback.
  ///
  /// If the request was served successfully, this will be null.
  final error;

  /// Whether the request was served successfully.
  bool get isSuccess => error == null;

  /// Whether the request was for a previously cached asset.
  final bool isCached;

  /// Whether the request was served unsuccessfully.
  bool get isFailure => !isSuccess;

  BarbackServerResult._success(this.url, this.id)
      : error = null,
        isCached = false;

  BarbackServerResult._cached(this.url, this.id)
      : error = null,
        isCached = true;

  BarbackServerResult._failure(this.url, this.id, this.error)
      : isCached = false;
}
