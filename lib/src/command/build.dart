// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;

import '../barback/asset_environment.dart';
import '../exit_codes.dart' as exit_codes;
import '../io.dart';
import '../log.dart' as log;
import '../source/hosted.dart';
import '../utils.dart';
import 'barback.dart';

final _arrow = getSpecial('\u2192', '=>');

/// Handles the `build` pub command.
class BuildCommand extends BarbackCommand {
  String get name => "build";
  String get description => "Apply transformers to build a package.";
  String get invocation => "pub build [options] [directories...]";
  String get docUrl => "http://dartlang.org/tools/pub/cmd/pub-build.html";
  List<String> get aliases => const ["deploy", "settle-up"];

  /// The path to the application's build output directory.
  String get outputDirectory => argResults["output"];

  List<String> get defaultSourceDirectories => ["web"];

  /// The number of files that have been built and written to disc so far.
  int builtFiles = 0;

  BuildCommand() {
    argParser.addOption("define",
        abbr: "D",
        help: "Defines an environment constant for dart2js.",
        allowMultiple: true,
        splitCommas: false);

    argParser.addOption("format",
        help: "How output should be displayed.",
        allowed: ["text", "json"],
        defaultsTo: "text");

    argParser.addOption("output",
        abbr: "o",
        help: "Directory to write build outputs to.",
        defaultsTo: "build");
  }

  Future onRunTransformerCommand() async {
    cleanDir(outputDirectory);

    var errorsJson = [];
    var logJson = [];

    var environmentConstants = new Map<String, String>.fromIterable(
        argResults["define"],
        key: (pair) => pair.split("=").first,
        value: (pair) => pair.split("=").last);

    try {
      // Since this server will only be hit by the transformer loader and isn't
      // user-facing, just use an IPv4 address to avoid a weird bug on the OS X
      // buildbots.
      var environment = await AssetEnvironment.create(entrypoint, mode,
          environmentConstants: environmentConstants, compiler: compiler);

      var hasError = false;

      // Unified error handler for barback and dartdevc.
      logError(error, {bool logToStdError = true}) {
        if (logToStdError) log.error(log.red("Build error:\n$error"));
        hasError = true;

        if (log.json.enabled) {
          // Wrap the error in a map in case we end up decorating it with
          // more properties later.
          errorsJson.add({"error": error.toString()});
        }
      }

      // Show in-progress errors, but not results. Those get handled
      // implicitly by getAllAssets().
      environment.barback.errors.listen(logError);

      // If we're using JSON output, the regular server logging is disabled.
      // Instead, we collect it here to include in the final JSON result.
      if (log.json.enabled) {
        environment.barback.log
            .listen((entry) => logJson.add(_logEntryToJson(entry)));
      }

      var assets = await log
          .progress/*<AssetSet>*/("Building ${entrypoint.root.name}", () async {
        // Register all of the build directories.
        // TODO(rnystrom): We don't actually need to bind servers for these, we
        // just need to add them to barback's sources. Add support to
        // BuildEnvironment for going the latter without the former.
        await Future.wait(
            sourceDirectories.map((dir) => environment.serveDirectory(dir)));

        return environment.barback.getAllAssets();
      });

      // Add all the js assets from dartdevc to the build, we don't need the
      // rest once a build is complete.
      if (environment.dartDevcEnvironment != null) {
        await log.progress("Building dartdevc modules", () async {
          assets.addAll(await environment.dartDevcEnvironment.doFullBuild(
              assets,
              logError: (e) => logError(e, logToStdError: false)));
        });
        await environment.dartDevcEnvironment.cleanUp();
      }

      // Clean up the environment before exiting.
      await environment.cleanUp();

      if (hasError) {
        log.error(log.red("Build failed."));
        log.json.message(
            {"buildResult": "failure", "errors": errorsJson, "log": logJson});
        return flushThenExit(exit_codes.DATA);
      } else {
        // Find all of the JS entrypoints we built.
        var dart2JSEntrypoints = assets
            .where((asset) => asset.id.path.endsWith(".dart.js"))
            .map((asset) => asset.id);

        await Future.wait(assets.map(_writeAsset));
        await _copyBrowserJsFiles(dart2JSEntrypoints, assets);

        log.message('Built $builtFiles ${pluralize('file', builtFiles)} '
            'to "$outputDirectory".');
        log.json.message({
          "buildResult": "success",
          "outputDirectory": outputDirectory,
          "numFiles": builtFiles,
          "log": logJson
        });
      }
    } on BarbackException catch (_) {
      // If [getAllAssets()] throws a BarbackException, the error has already
      // been reported.
      log.error(log.red("Build failed."));
      log.json.message(
          {"buildResult": "failure", "errors": errorsJson, "log": logJson});

      return flushThenExit(exit_codes.DATA);
    }
  }

  /// Writes [asset] to the appropriate build directory.
  ///
  /// If [asset] is in the special "packages" directory, writes it to every
  /// build directory.
  Future _writeAsset(Asset asset) async {
    // In release mode, strip out .dart files since all relevant ones have been
    // compiled to JavaScript already.
    if (mode == BarbackMode.RELEASE && asset.id.extension == ".dart") {
      return null;
    }

    var destPath = _idToPath(asset.id);

    // If the asset is from a public directory, copy it into all of the
    // top-level build directories.
    if (path.isWithin("packages", destPath)) {
      return Future.wait(sourceDirectories.map((buildDir) =>
          _writeOutputFile(asset, path.join(buildDir, destPath))));
    }

    return _writeOutputFile(asset, destPath);
  }

  /// Converts [id] to a relative path in the output directory for that asset.
  ///
  /// This corresponds to the URL that could be used to request that asset from
  /// pub serve.
  ///
  /// Examples (where entrypoint is "myapp"):
  ///
  ///     myapp|web/index.html   -> web/index.html
  ///     myapp|lib/lib.dart     -> packages/myapp/lib.dart
  ///     foo|lib/foo.dart       -> packages/foo/foo.dart
  ///     myapp|test/main.dart   -> test/main.dart
  ///     foo|test/main.dart     -> ERROR
  ///
  /// Throws a [FormatException] if [id] is not a valid public asset.
  String _idToPath(AssetId id) {
    var parts = path.split(path.fromUri(id.path));

    if (parts.length < 2) {
      throw new FormatException(
          "Can not build assets from top-level directory.");
    }

    // Map "lib" to the "packages" directory.
    if (parts[0] == "lib") {
      return path.join("packages", id.package, path.joinAll(parts.skip(1)));
    }

    // Shouldn't be trying to access non-public directories of other packages.
    assert(id.package == entrypoint.root.name);

    // Allow any path in the entrypoint package.
    return path.joinAll(parts);
  }

  /// Writes the contents of [asset] to [relativePath] within the build
  /// directory.
  Future _writeOutputFile(Asset asset, String relativePath) {
    builtFiles++;
    var destPath = path.join(outputDirectory, relativePath);
    ensureDir(path.dirname(destPath));
    return createFileFromStream(asset.read(), destPath);
  }

  /// If this package depends directly on the `browser` package, this ensures
  /// that the JavaScript bootstrap files are copied into `packages/browser/`
  /// directories next to each entrypoint in [entrypoints].
  Future _copyBrowserJsFiles(Iterable<AssetId> entrypoints, AssetSet assets) {
    // Must depend on the browser package.
    if (!entrypoint.root.immediateDependencies
        .any((dep) => dep.name == 'browser' && dep.source is HostedSource)) {
      return new Future.value();
    }

    // Get all of the subdirectories that contain Dart entrypoints.
    var entrypointDirs = entrypoints
        // Convert the asset path to a native-separated one and get the
        // directory containing the entrypoint.
        .map((id) => path.dirname(path.fromUri(id.path)))
        // Don't copy files to the top levels of the build directories since
        // the normal lib asset copying will take care of that.
        .where((dir) => path.split(dir).length > 1)
        .toSet();

    var jsAssets = assets.where((asset) =>
        asset.id.package == 'browser' && asset.id.extension == '.js');
    return Future.wait(entrypointDirs.expand((dir) {
      // TODO(nweiz): we should put browser JS files next to any HTML file
      // rather than any entrypoint. An HTML file could import an entrypoint
      // that's not adjacent.
      return jsAssets.map((asset) {
        var jsPath = path.join(dir, _idToPath(asset.id));
        return _writeOutputFile(asset, jsPath);
      });
    }));
  }

  /// Converts [entry] to a JSON object for use with JSON-formatted output.
  Map _logEntryToJson(LogEntry entry) {
    var data = {
      "level": entry.level.name,
      "transformer": {
        "name": entry.transform.transformer.toString(),
        "primaryInput": {
          "package": entry.transform.primaryId.package,
          "path": entry.transform.primaryId.path
        },
      },
      "assetId": {"package": entry.assetId.package, "path": entry.assetId.path},
      "message": entry.message
    };

    if (entry.span != null) {
      data["span"] = {
        "url": entry.span.sourceUrl,
        "start": {
          "line": entry.span.start.line,
          "column": entry.span.start.column
        },
        "end": {"line": entry.span.end.line, "column": entry.span.end.column},
      };
    }

    return data;
  }
}
