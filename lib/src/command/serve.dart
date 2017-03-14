// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:barback/barback.dart';

import '../barback/asset_environment.dart';
import '../log.dart' as log;
import '../utils.dart';
import 'barback.dart';

final _arrow = getSpecial('\u2192', '=>');

/// Handles the `serve` pub command.
class ServeCommand extends BarbackCommand {
  String get name => "serve";
  String get description =>
      'Run a local web development server.\n\n'
      'By default, this serves "web/" and "test/", but an explicit list of \n'
      'directories to serve can be provided as well.';
  String get invocation => "pub serve [directories...]";
  String get docUrl => "http://dartlang.org/tools/pub/cmd/pub-serve.html";

  String get hostname => argResults['hostname'];

  /// The base port for the servers.
  ///
  /// This will print a usage error and exit if the specified port is invalid.
  int get port => parseInt(argResults['port'], 'port');

  /// The port for the admin UI.
  ///
  /// This will print a usage error and exit if the specified port is invalid.
  int get adminPort {
    var adminPort = argResults['admin-port'];
    return adminPort == null ? null : parseInt(adminPort, 'admin port');
  }

  /// `true` if Dart entrypoints should be compiled to JavaScript.
  bool get useDart2JS => argResults['dart2js'];

  /// `true` if the admin server URL should be displayed on startup.
  bool get logAdminUrl => argResults['log-admin-url'];

  BarbackMode get defaultMode => BarbackMode.DEBUG;

  List<String> get defaultSourceDirectories => ["web", "test"];

  RegExp get rewriteFilterRegExp {
    String pathFilterRegExpArg = argResults['rewrite-to-index'];
    if (pathFilterRegExpArg == null) return null;
    try {
      return new RegExp(pathFilterRegExpArg);
    } catch (FormatException) {
      log.error(log.red('Invalid regexp: $pathFilterRegExpArg'));
      return null;
    }
  }

  /// This completer is used to keep pub running (by not completing) and to
  /// pipe fatal errors to pub's top-level error-handling machinery.
  final _completer = new Completer();

  ServeCommand() {
    argParser.addOption("define", abbr: "D",
        help: "Defines an environment constant for dart2js.",
        allowMultiple: true, splitCommas: false);
    argParser.addOption('hostname', defaultsTo: 'localhost',
        help: 'The hostname to listen on.');
    argParser.addOption('port', defaultsTo: '8080',
        help: 'The base port to listen on.');

    // TODO(rnystrom): A hidden option to print the URL that the admin server
    // is bound to on startup. Since this is currently only used for the Web
    // Socket interface, we don't want to show it to users, but the tests and
    // Editor need this logged to know what port to bind to.
    // Remove this (and always log) when #16954 is fixed.
    argParser.addFlag('log-admin-url', defaultsTo: false, hide: true);

    // TODO(nweiz): Make this public when issue 16954 is fixed.
    argParser.addOption('admin-port', hide: true);

    argParser.addFlag('dart2js', defaultsTo: true,
        help: 'Compile Dart to JavaScript.');
    argParser.addFlag('force-poll', defaultsTo: false,
        help: 'Force the use of a polling filesystem watcher.');
    argParser.addOption('rewrite-to-index',
        help: 'Redirected to "index.html" 404 requests with paths matching the given regexp.');
  }

  Future onRunTransformerCommand() async {
    var port = parseInt(argResults['port'], 'port');
    var adminPort = argResults['admin-port'] == null ? null :
        parseInt(argResults['admin-port'], 'admin port');

    var watcherType = argResults['force-poll'] ?
        WatcherType.POLLING : WatcherType.AUTO;

    var environmentConstants = new Map<String, String>.fromIterable(
        argResults["define"],
        key: (pair) => pair.split("=").first,
        value: (pair) => pair.split("=").last);

    var environment = await AssetEnvironment.create(entrypoint, mode,
        watcherType: watcherType, hostname: hostname, basePort: port,
        useDart2JS: useDart2JS, environmentConstants: environmentConstants);
    var directoryLength = sourceDirectories.map((dir) => dir.length)
        .reduce(math.max);

    if (adminPort != null) {
      var server = await environment.startAdminServer(adminPort);
      server.results.listen((_) {
        // The admin server produces no result values.
        assert(false);
      }, onError: _fatalError);

      if (logAdminUrl) {
        log.message("Running admin server on "
                    "${log.bold('http://$hostname:${server.port}')}");
      }
    }

    // Start up the servers. We pause updates while this is happening so
    // that we don't log spurious build results in the middle of listing
    // out the bound servers.
    environment.pauseUpdates();
    for (var directory in sourceDirectories) {
      await _startServer(environment, directory, directoryLength);
    }

    // Now that the servers are up and logged, send them to barback.
    environment.barback.errors.listen((error) {
      log.error(log.red("Build error:\n$error"));
    });

    environment.barback.results.listen((result) {
      if (result.succeeded) {
        // TODO(rnystrom): Report using growl/inotify-send where available.
        log.message("Build completed ${log.green('successfully')}");
      } else {
        log.message("Build completed with "
            "${log.red(result.errors.length)} errors.");
      }
    }, onError: _fatalError);

    environment.resumeUpdates();
    await _completer.future;
  }

  Future _startServer(AssetEnvironment environment, String rootDirectory,
      int directoryLength) async {
    var server = await environment.serveDirectory(rootDirectory);
    // In release mode, strip out .dart files since all relevant ones have
    // been compiled to JavaScript already.
    if (mode == BarbackMode.RELEASE) {
      server.allowAsset = (url) => !url.path.endsWith(".dart");
    }
    if (rewriteFilterRegExp != null) {
      server.rewriteFilter = (url) => rewriteFilterRegExp.hasMatch(url.path);
    }

    // Add two characters to account for "[" and "]".
    var directory = log.gray(
        padRight("[${server.rootDirectory}]", directoryLength + 2));

    server.results.listen((result) {
      if (result.isCached) {
        var prefix = "$directory ${log.green('GET')}";
        log.collapsible(
            "$prefix ${result.url.path} $_arrow (cached) ${result.id}",
            "$prefix Served ## cached assets.");
      } else if (result.isSuccess) {
        var prefix = "$directory ${log.green('GET')}";
        log.collapsible("$prefix ${result.url.path} $_arrow ${result.id}",
            "$prefix Served ## assets.");
      } else {
        var buffer = new StringBuffer();
        buffer.write("$directory ${log.red('GET')} ${result.url.path} $_arrow");

        var error = result.error.toString();
        if (error.contains("\n")) {
          buffer.write("\n${prefixLines(error)}");
        } else {
          buffer.write(" $error");
        }

        log.error(buffer);
      }
    }, onError: _fatalError);

    log.message("Serving ${entrypoint.root.name} "
        "${padRight(server.rootDirectory, directoryLength)} "
        "on ${log.bold('http://$hostname:${server.port}')}");
  }

  /// Reports [error] and exits the server.
  void _fatalError(error, [stackTrace]) {
    if (_completer.isCompleted) return;
    _completer.completeError(error, stackTrace);
  }
}
