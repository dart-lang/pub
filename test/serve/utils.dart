// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:pub/src/compiler.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

/// The pub process running "pub serve".
TestProcess _pubServer;

/// The ephemeral port assign to the running admin server.
int _adminPort;

/// The ephemeral ports assigned to the running servers, associated with the
/// directories they're serving.
final _ports = new Map<String, int>();

/// The web socket connection to the running pub process, or `null` if no
/// connection has been made.
WebSocket _webSocket;
Stream _webSocketBroadcastStream;

/// The code for a transformer that renames ".txt" files to ".out" and adds a
/// ".out" suffix.
const REWRITE_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class RewriteTransformer extends Transformer {
  RewriteTransformer.asPlugin();

  String get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      var id = transform.primaryInput.id.changeExtension(".out");
      transform.addOutput(new Asset.fromString(id, "\$contents.out"));
    });
  }
}
""";

/// The code for a lazy version of [REWRITE_TRANSFORMER].
const LAZY_TRANSFORMER = """
import 'dart:async';

import 'package:barback/barback.dart';

class LazyRewriteTransformer extends Transformer implements LazyTransformer {
  LazyRewriteTransformer.asPlugin();

  String get allowedExtensions => '.txt';

  Future apply(Transform transform) {
    transform.logger.info('Rewriting \${transform.primaryInput.id}.');
    return transform.primaryInput.readAsString().then((contents) {
      var id = transform.primaryInput.id.changeExtension(".out");
      transform.addOutput(new Asset.fromString(id, "\$contents.out"));
    });
  }

  Future declareOutputs(DeclaringTransform transform) {
    transform.declareOutput(transform.primaryId.changeExtension(".out"));
    return new Future.value();
  }
}
""";

/// The web socket error code for a directory not being served.
const NOT_SERVED = 1;

/// Returns the source code for a Dart library defining a Transformer that
/// rewrites Dart files.
///
/// The transformer defines a constant named TOKEN whose value is [id]. When the
/// transformer transforms another Dart file, it will look for a "TOKEN"
/// constant definition there and modify it to include *this* transformer's
/// TOKEN value as well.
///
/// If [import] is passed, it should be the name of a package that defines its
/// own TOKEN constant. The primary library of that package will be imported
/// here and its TOKEN value will be added to this library's.
///
/// This transformer takes one configuration field: "addition". This is
/// concatenated to its TOKEN value before adding it to the output library.
String dartTransformer(String id, {String import}) {
  if (import != null) {
    id = '$id imports \${$import.TOKEN}';
    import = 'import "package:$import/$import.dart" as $import;';
  } else {
    import = '';
  }

  return """
import 'dart:async';

import 'package:barback/barback.dart';
$import

import 'dart:io';

const TOKEN = "$id";

final _tokenRegExp = new RegExp(r'^const TOKEN = "(.*?)";\$', multiLine: true);

class DartTransformer extends Transformer {
  final BarbackSettings _settings;

  DartTransformer.asPlugin(this._settings);

  String get allowedExtensions => '.dart';

  Future apply(Transform transform) {
    return transform.primaryInput.readAsString().then((contents) {
      transform.addOutput(new Asset.fromString(transform.primaryInput.id,
          contents.replaceAllMapped(_tokenRegExp, (match) {
        var token = TOKEN;
        var addition = _settings.configuration["addition"];
        if (addition != null) token += addition;
        return 'const TOKEN = "(\${match[1]}, \$token)";';
      })));
    });
  }
}
""";
}

/// Starts the `pub serve` process.
///
/// Unlike [pubServe], this doesn't determine the port number of the server, and
/// so may be used to test for errors in the initialization process.
///
/// Returns the `pub serve` process.
Future<TestProcess> startPubServe(
    {Iterable<String> args, bool createWebDir: true, Compiler compiler}) async {
  var pubArgs = [
    "serve",
    "--port=0", // Use port 0 to get an ephemeral port.
    "--force-poll",
    "--admin-port=0", // Use port 0 to get an ephemeral port.
    "--log-admin-url",
  ];
  if (compiler != null) {
    pubArgs.add("--web-compiler=${compiler.name}");
  }

  if (args != null) pubArgs.addAll(args);

  if (createWebDir) await d.dir(appPath, [d.dir("web")]).create();
  return await startPub(args: pubArgs);
}

/// Starts the "pub serve" process and records its port number for future
/// requests.
///
/// The port can be retrieved by calling [getServerUrl].
///
/// If [createWebDir] is `true`, creates a `web/` directory if one doesn't exist
/// so pub doesn't complain about having nothing to serve.
///
/// Returns the `pub serve` process.
Future<TestProcess> pubServe(
    {bool createWebDir: true, Iterable<String> args, Compiler compiler}) async {
  _pubServer = await startPubServe(
      args: args, createWebDir: createWebDir, compiler: compiler);

  addTearDown(() {
    _ports.clear();

    if (_webSocket != null) {
      _webSocket.close();
      _webSocket = null;
      _webSocketBroadcastStream = null;
    }
  });

  await expectLater(
      _pubServer.stdout, emits(startsWith("Loading source assets...")));
  await expectLater(_pubServer.stdout,
      mayEmitMultiple(matches("Loading .* transformers...")));

  _adminPort = _parseAdminPort(await _pubServer.stdout.next);

  // The server should emit one or more ports.
  while (_parsePort(await _pubServer.stdout.peek)) {
    await _pubServer.stdout.next;
  }
  expect(_ports, isNotEmpty);

  return _pubServer;
}

/// The regular expression for parsing pub's output line describing the URL for
/// the server.
final _parsePortRegExp = new RegExp(r"([^ ]+) +on http://localhost:(\d+)");

/// Parses the port number from the "Running admin server on localhost:1234"
/// line printed by pub serve.
int _parseAdminPort(String line) {
  expect(line, startsWith('Running admin server on'));
  expect(line, contains(_parsePortRegExp));

  var match = _parsePortRegExp.firstMatch(line);
  return int.parse(match[2]);
}

/// Parses the port number from the "Serving blah on localhost:1234" line
/// printed by pub serve and adds it to [_ports].
///
/// Returns whether parsing succeeded.
bool _parsePort(String line) {
  var match = _parsePortRegExp.firstMatch(line);
  if (match == null) return false;
  _ports[match[1]] = int.parse(match[2]);
  return true;
}

Future endPubServe() => _pubServer.kill();

/// Makes an HTTP request to the running pub server with [urlPath] and returns
/// the response.
///
/// [root] indicates which server should be accessed, and defaults to "web".
Future<http.Response> requestFromPub(String urlPath,
        {String root, Map<String, String> headers}) =>
    http.get(getServerUrl(root, urlPath), headers: headers);

/// Makes an HTTP request to the running pub server with [urlPath] and
/// verifies that it responds with a body that matches [expectation].
///
/// [expectation] may either be a [Matcher] or a string to match an exact body.
/// [root] indicates which server should be accessed, and defaults to "web".
/// [headers] may be either a [Matcher] or a map to match an exact headers map.
Future requestShouldSucceed(String urlPath, expectation,
    {String root, headers}) async {
  var response = await requestFromPub(urlPath, root: root);
  expect(response.statusCode, equals(200));
  if (expectation != null) expect(response.body, expectation);
  if (headers != null) expect(response.headers, headers);
}

/// Makes an HTTP request to the running pub server with [urlPath] and verifies
/// that it responds with a 404.
///
/// [root] indicates which server should be accessed, and defaults to "web".
Future requestShould404(String urlPath, {String root}) async {
  var response = await requestFromPub(urlPath, root: root);
  expect(response.statusCode, equals(404));
}

/// Makes an HTTP request to the running pub server with [urlPath] and verifies
/// that it responds with a redirect to the given [redirectTarget].
///
/// [redirectTarget] may be either a [Matcher] or a string to match an exact
/// URL. [root] indicates which server should be accessed, and defaults to
/// "web".
Future requestShouldRedirect(String urlPath, redirectTarget,
    {String root}) async {
  var request = new http.Request("GET", Uri.parse(getServerUrl(root, urlPath)));
  request.followRedirects = false;
  var response = await request.send();
  expect(response.statusCode ~/ 100, equals(3));
  expect(response.headers, containsPair('location', redirectTarget));
}

/// Makes an HTTP POST to the running pub server with [urlPath] and verifies
/// that it responds with a 405.
///
/// [root] indicates which server should be accessed, and defaults to "web".
Future postShould405(String urlPath, {String root}) async {
  var response = await http.post(getServerUrl(root, urlPath));
  expect(response.statusCode, equals(405));
}

/// Makes an HTTP request to the (theoretically) running pub server with
/// [urlPath] and verifies that it cannot be connected to.
///
/// [root] indicates which server should be accessed, and defaults to "web".
Future requestShouldNotConnect(String urlPath, {String root}) {
  return expectLater(http.get(getServerUrl(root, urlPath)),
      throwsA(new isInstanceOf<SocketException>()));
}

/// Reads lines from pub serve's stdout until it prints the build success
/// message.
///
/// The schedule will not proceed until the output is found. If not found, it
/// will eventually time out.
Future waitForBuildSuccess() =>
    expectLater(_pubServer.stdout, emitsThrough(contains("successfully")));

/// Opening a web socket connection to the currently running pub serve.
Future _ensureWebSocket() async {
  // Use the existing one if already connected.
  if (_webSocket != null) return;

  // Server should already be running.
  expect(_pubServer, isNotNull);
  expect(_adminPort, isNotNull);

  var socket = await WebSocket.connect("ws://localhost:$_adminPort");
  _webSocket = socket;
  // TODO(rnystrom): Works around #13913.
  _webSocketBroadcastStream = _webSocket.map(JSON.decode).asBroadcastStream();
}

/// Closes the web socket connection to the currently-running pub serve.
Future closeWebSocket() async {
  await _ensureWebSocket();
  await _webSocket.close();
  _webSocket = null;
}

/// Sends a JSON RPC 2.0 request to the running pub serve's web socket
/// connection.
///
/// This calls a method named [method] with the given [params] (or no
/// parameters, if it's not passed).
///
/// Returns the result of the RPC call.
Future<Map> webSocketRequest(String method, [Map params]) async {
  await _ensureWebSocket();
  return await _jsonRpcRequest(method, params);
}

/// Sends a JSON RPC 2.0 request to the running pub serve's web socket
/// connection, waits for a reply, then verifies the result.
///
/// This calls a method named [method] with the given [params].
///
/// The result is validated using [result], which may be a [Matcher] or a [Map]
/// containing [Matcher]s.
///
/// Returns the result of the RPC call.
Future<Map> expectWebSocketResult(String method, Map params, result) async {
  var response = await webSocketRequest(method, params);
  expect(response["result"], result);
  return response["result"];
}

/// Sends a JSON RPC 2.0 request to the running pub serve's web socket
/// connection, waits for a reply, then verifies the error response.
///
/// This calls a method named [method] with the given [params].
///
/// The error response is validated using [errorCode] and [errorMessage]. Both
/// of these must be provided. The error code is checked against [errorCode] and
/// the error message is checked against [errorMessage]. Either of these may be
/// matchers.
///
/// If [data] is provided, it is a JSON value or matcher used to validate the
/// "data" value of the error response.
///
/// Returns the result of the RPC call.
Future expectWebSocketError(String method, Map params, errorCode, errorMessage,
    {data}) async {
  var response = await webSocketRequest(method, params);
  expect(response["error"]["code"], errorCode);
  expect(response["error"]["message"], errorMessage);

  if (data != null) {
    expect(response["error"]["data"], data);
  }

  return response["error"]["data"];
}

/// Validates that [root] was not bound to a port when pub serve started.
void expectNotServed(String root) {
  expect(_ports.containsKey(root), isFalse);
}

/// The next id to use for a JSON-RPC 2.0 request.
var _rpcId = 0;

/// Sends a JSON-RPC 2.0 request calling [method] with [params].
///
/// Returns the response object.
Future<Map> _jsonRpcRequest(String method, [Map params]) async {
  var id = _rpcId++;
  var message = {"jsonrpc": "2.0", "method": method, "id": id};
  if (params != null) message["params"] = params;
  _webSocket.add(JSON.encode(message));

  var value = await _webSocketBroadcastStream
      .firstWhere((response) => response["id"] == id);
  printOnFailure("Web Socket request $method with params $params\n"
      "Result: $value");

  expect(value["id"], equals(id));
  return value;
}

/// Returns the URL for the server serving [path] from [root].
///
/// If [root] is omitted, defaults to "web". If [path] is omitted, no path is
/// included. The Future will complete once the server is up and running and
/// the bound ports are known.
String getServerUrl([String root, String path]) {
  if (root == null) root = 'web';
  expect(_ports, contains(root));
  var url = "http://localhost:${_ports[root]}";
  if (path != null) url = "$url/$path";
  return url;
}

/// Records that [root] has been bound to [port].
///
/// Used for testing the Web Socket API for binding new root directories to
/// ports after pub serve has been started.
void registerServerPort(String root, int port) {
  _ports[root] = port;
}
