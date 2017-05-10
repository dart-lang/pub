// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'package:watcher/watcher.dart';

import '../cached_package.dart';
import '../dart.dart' as dart;
import '../entrypoint.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_graph.dart';
import '../source/cached.dart';
import '../utils.dart';
import 'dartdevc/dartdevc_environment.dart';
import 'admin_server.dart';
import 'barback_server.dart';
import 'compiler.dart';
import 'dart_forwarding_transformer.dart';
import 'dart2js_transformer.dart';
import 'load_all_transformers.dart';
import 'pub_package_provider.dart';
import 'source_directory.dart';

/// The entire "visible" state of the assets of a package and all of its
/// dependencies, taking into account the user's configuration when running pub.
///
/// Where [PackageGraph] just describes the entrypoint's dependencies as
/// specified by pubspecs, this includes "transient" information like the mode
/// that the user is running pub in, or which directories they want to
/// transform.
class AssetEnvironment {
  /// Creates a new build environment for working with the assets used by
  /// [entrypoint] and its dependencies.
  ///
  /// HTTP servers that serve directories from this environment will be bound
  /// to [hostname] and have ports based on [basePort]. If omitted, they
  /// default to "localhost" and "0" (use ephemeral ports), respectively.
  ///
  /// Loads all used transformers using [mode] (including dart2js or dartdevc
  /// based on [compiler]).
  ///
  /// This will only add the root package's "lib" directory to the environment.
  /// Other directories can be added to the environment using [serveDirectory].
  ///
  /// If [watcherType] is not [WatcherType.NONE] (the default), watches source
  /// assets for modification.
  ///
  /// If [packages] is passed, only those packages' assets are loaded and
  /// served.
  ///
  /// If [entrypoints] is passed, only transformers necessary to run those
  /// entrypoints are loaded. Each entrypoint is expected to refer to a Dart
  /// library.
  ///
  /// If [environmentConstants] is passed, the constants it defines are passed
  /// on to the built-in dart2js transformer.
  ///
  /// Returns a [Future] that completes to the environment once the inputs,
  /// transformers, and server are loaded and ready.
  static Future<AssetEnvironment> create(
      Entrypoint entrypoint, BarbackMode mode,
      {WatcherType watcherType,
      String hostname,
      int basePort,
      Iterable<String> packages,
      Iterable<AssetId> entrypoints,
      Map<String, String> environmentConstants,
      Compiler compiler}) {
    watcherType ??= WatcherType.NONE;
    hostname ??= "localhost";
    basePort ??= 0;
    environmentConstants ??= {};
    compiler ??= Compiler.dart2JS;

    return log.progress("Loading asset environment", () async {
      var graph = _adjustPackageGraph(entrypoint.packageGraph, mode, packages);
      var barback = new Barback(new PubPackageProvider(graph, compiler));
      DartDevcEnvironment dartDevcEnvironment;
      if (compiler == Compiler.dartDevc) {
        dartDevcEnvironment =
            new DartDevcEnvironment(barback, mode, environmentConstants, graph);
      }
      barback.log.listen(_log);

      var environment = new AssetEnvironment._(graph, barback, mode,
          watcherType, hostname, basePort, environmentConstants, compiler,
          dartDevcEnvironment: dartDevcEnvironment);

      await environment._load(entrypoints: entrypoints);
      return environment;
    }, fine: true);
  }

  /// Return a version of [graph] that's restricted to [packages] (if passed)
  /// and loads cached packages (if [mode] is [BarbackMode.DEBUG]).
  static PackageGraph _adjustPackageGraph(
      PackageGraph graph, BarbackMode mode, Iterable<String> packages) {
    if (mode != BarbackMode.DEBUG && packages == null) return graph;
    packages = (packages == null ? graph.packages.keys : packages).toSet();

    return new PackageGraph(
        graph.entrypoint,
        graph.lockFile,
        new Map.fromIterable(packages, value: (packageName) {
          var package = graph.packages[packageName];
          if (mode != BarbackMode.DEBUG) return package;
          var cache = path.join('.pub/deps/debug', packageName);
          if (!dirExists(cache)) return package;
          return new CachedPackage(package, cache);
        }));
  }

  /// The server for the Web Socket API and admin interface.
  AdminServer _adminServer;

  final DartDevcEnvironment dartDevcEnvironment;

  /// The public directories in the root package that are included in the asset
  /// environment, keyed by their root directory.
  final _directories = new Map<String, SourceDirectory>();

  /// The [Barback] instance used to process assets in this environment.
  final Barback barback;

  /// The root package being built.
  Package get rootPackage => graph.entrypoint.root;

  /// The graph of packages whose assets and transformers are loaded in this
  /// environment.
  ///
  /// This isn't necessarily identical to the graph that's passed in to the
  /// environment. It may expose fewer packages if some packages' assets don't
  /// need to be loaded, and it may expose some [CachedPackage]s.
  final PackageGraph graph;

  /// The mode to run the transformers in.
  final BarbackMode mode;

  /// Constants to passed to the built-in dart2js transformer.
  final Map<String, String> environmentConstants;

  /// How source files should be watched.
  final WatcherType _watcherType;

  /// The hostname that servers are bound to.
  final String _hostname;

  /// The starting number for ports that servers will be bound to.
  ///
  /// Servers will be bound to ports starting at this number and then
  /// incrementing from there. However, if this is zero, then ephemeral port
  /// numbers will be selected for each server.
  final int _basePort;

  /// The modified source assets that have not been sent to barback yet.
  ///
  /// The build environment can be paused (by calling [pauseUpdates]) and
  /// resumed ([resumeUpdates]). While paused, all source asset updates that
  /// come from watching or adding new directories are not sent to barback.
  /// When resumed, all pending source updates are sent to barback.
  ///
  /// This lets pub serve and pub build create an environment and bind several
  /// servers before barback starts building and producing results
  /// asynchronously.
  ///
  /// If this is `null`, then the environment is "live" and all updates will
  /// go to barback immediately.
  Set<AssetId> _modifiedSources;

  /// The compiler mode for this environment.
  final Compiler compiler;

  AssetEnvironment._(this.graph, this.barback, this.mode, this._watcherType,
      this._hostname, this._basePort, this.environmentConstants, this.compiler,
      {this.dartDevcEnvironment});

  /// Gets the built-in [Transformer]s or [AggregateTransformer]s that should be
  /// added to [package].
  ///
  /// Returns `null` if there are none.
  Iterable<Set> getBuiltInTransformers(Package package) {
    var transformers = <List>[];

    var isRootPackage = package.name == rootPackage.name;
    switch (compiler) {
      case Compiler.dart2JS:
        // the dart2js transformer only runs on the root package.
        if (isRootPackage) {
          // If the entrypoint package manually configures the dart2js
          // transformer, don't include it in the built-in transformer list.
          //
          // TODO(nweiz): if/when we support more built-in transformers, make
          // this more general.
          var containsDart2JS = graph.entrypoint.root.pubspec.transformers.any(
              (transformers) => transformers
                  .any((config) => config.id.package == '\$dart2js'));

          if (!containsDart2JS && compiler == Compiler.dart2JS) {
            transformers.add([
              new Dart2JSTransformer(this, mode),
              new DartForwardingTransformer(),
            ]);
          }
        }
    }

    return transformers.map((list) => list.toSet());
  }

  /// Starts up the admin server on an appropriate port and returns it.
  ///
  /// This may only be called once on the build environment.
  Future<AdminServer> startAdminServer(int port) {
    // Can only start once.
    assert(_adminServer == null);

    return AdminServer
        .bind(this, _hostname, port)
        .then((server) => _adminServer = server);
  }

  /// Binds a new port to serve assets from within [rootDirectory] in the
  /// entrypoint package.
  ///
  /// Adds and watches the sources within that directory. Returns a [Future]
  /// that completes to the bound server.
  ///
  /// If [rootDirectory] is already being served, returns that existing server.
  Future<BarbackServer> serveDirectory(String rootDirectory) async {
    // See if there is already a server bound to the directory.
    var directory = _directories[rootDirectory];
    if (directory != null) {
      return directory.server.then((server) {
        log.fine('Already serving $rootDirectory on ${server.url}.');
        return server;
      });
    }

    // See if the new directory overlaps any existing servers.
    var overlapping = _directories.keys
        .where((directory) =>
            path.isWithin(directory, rootDirectory) ||
            path.isWithin(rootDirectory, directory))
        .toList();

    if (overlapping.isNotEmpty) {
      return new Future.error(
          new OverlappingSourceDirectoryException(overlapping));
    }

    var port = _basePort;

    // If not using an ephemeral port, find the lowest-numbered available one.
    if (port != 0) {
      var boundPorts =
          _directories.values.map((directory) => directory.port).toSet();
      while (boundPorts.contains(port)) {
        port++;
      }
    }

    var sourceDirectory =
        new SourceDirectory(this, rootDirectory, _hostname, port);
    _directories[rootDirectory] = sourceDirectory;

    sourceDirectory.watchSubscription =
        await _provideDirectorySources(rootPackage, rootDirectory);
    return await sourceDirectory.serve(
        dartDevcEnvironment: dartDevcEnvironment);
  }

  /// Binds a new port to serve assets from within the "bin" directory of
  /// [package].
  ///
  /// Adds the sources within that directory and then binds a server to it.
  /// Unlike [serveDirectory], this works with packages that are not the
  /// entrypoint.
  ///
  /// Returns a [Future] that completes to the bound server.
  Future<BarbackServer> servePackageBinDirectory(String package) {
    return _provideDirectorySources(graph.packages[package], "bin").then((_) =>
        BarbackServer.bind(this, _hostname, 0,
            package: package, rootDirectory: "bin"));
  }

  /// Precompiles all of [packageName]'s executables to snapshots in
  /// [directory].
  ///
  /// If [executableIds] is passed, only those executables are precompiled.
  ///
  /// Returns a map from executable name to path for the snapshots that were
  /// successfully precompiled.
  Future<Map<String, String>> precompileExecutables(
      String packageName, String directory,
      {Iterable<AssetId> executableIds}) async {
    if (executableIds == null) {
      executableIds = graph.packages[packageName].executableIds;
    }

    log.fine("Executables for $packageName: $executableIds");
    if (executableIds.isEmpty) return {};

    var server = await servePackageBinDirectory(packageName);
    try {
      var precompiled = {};
      await waitAndPrintErrors(executableIds.map((id) async {
        var basename = path.url.basename(id.path);
        var snapshotPath = path.join(directory, "$basename.snapshot");
        await dart.snapshot(server.url.resolve(basename), snapshotPath, id: id);
        precompiled[path.withoutExtension(basename)] = snapshotPath;
      }));

      return precompiled;
    } finally {
      // Don't await this future, since we have no need to wait for the server
      // to fully shut down.
      server.close();
    }
  }

  /// Stops the server bound to [rootDirectory].
  ///
  /// Also removes any source files within that directory from barback. Returns
  /// the URL of the unbound server, of `null` if [rootDirectory] was not
  /// bound to a server.
  Future<Uri> unserveDirectory(String rootDirectory) async {
    log.fine("Unserving $rootDirectory.");
    var directory = _directories.remove(rootDirectory);
    if (directory == null) return new Future.value();

    var url = (await directory.server).url;
    await directory.close();
    _removeDirectorySources(rootDirectory);
    return url;
  }

  /// Gets the source directory that contains [assetPath] within the entrypoint
  /// package.
  ///
  /// If [assetPath] is not contained within a source directory, this throws
  /// an exception.
  String getSourceDirectoryContaining(String assetPath) => _directories.values
      .firstWhere((dir) => path.isWithin(dir.directory, assetPath))
      .directory;

  /// Return all URLs serving [assetPath] in this environment.
  Future<List<Uri>> getUrlsForAssetPath(String assetPath) async {
    // Check the three (mutually-exclusive) places the path could be pointing.
    var urls = await _lookUpPathInServerRoot(assetPath);
    if (urls.isEmpty) urls = await _lookUpPathInPackagesDirectory(assetPath);
    if (urls.isEmpty) urls = await _lookUpPathInDependency(assetPath);
    return urls;
  }

  /// Look up [assetPath] in the root directories of servers running in the
  /// entrypoint package.
  Future<List<Uri>> _lookUpPathInServerRoot(String assetPath) {
    // Find all of the servers whose root directories contain the asset and
    // generate appropriate URLs for each.
    return Future.wait(_directories.values
        .where((dir) => path.isWithin(dir.directory, assetPath))
        .map((dir) {
      var relativePath = path.relative(assetPath, from: dir.directory);
      return dir.server
          .then((server) => server.url.resolveUri(path.toUri(relativePath)));
    }));
  }

  /// Look up [assetPath] in the "packages" directory in the entrypoint package.
  Future<List<Uri>> _lookUpPathInPackagesDirectory(String assetPath) {
    var components = path.split(path.relative(assetPath));
    if (components.first != "packages") return new Future.value([]);
    if (!graph.packages.containsKey(components[1])) return new Future.value([]);
    return Future.wait(_directories.values.map((dir) {
      return dir.server
          .then((server) => server.url.resolveUri(path.toUri(assetPath)));
    }));
  }

  /// Look up [assetPath] in the "lib" or "asset" directory of a dependency
  /// package.
  Future<List<Uri>> _lookUpPathInDependency(String assetPath) {
    for (var packageName in graph.packages.keys) {
      var package = graph.packages[packageName];
      var libDir = package.path('lib');
      var assetDir = package.path('asset');

      var uri;
      if (path.isWithin(libDir, assetPath)) {
        uri = path.toUri(path.join(
            'packages', package.name, path.relative(assetPath, from: libDir)));
      } else if (path.isWithin(assetDir, assetPath)) {
        uri = path.toUri(path.join(
            'assets', package.name, path.relative(assetPath, from: assetDir)));
      } else {
        continue;
      }

      return Future.wait(_directories.values.map((dir) {
        return dir.server.then((server) => server.url.resolveUri(uri));
      }));
    }

    return new Future.value([]);
  }

  /// Given a URL to an asset served by this environment, returns the ID of the
  /// asset that would be accessed by that URL.
  ///
  /// If no server can serve [url], completes to `null`.
  Future<AssetId> getAssetIdForUrl(Uri url) {
    return Future
        .wait(_directories.values.map((dir) => dir.server))
        .then((servers) {
      var server = servers.firstWhere((server) {
        if (server.port != url.port) return false;
        return isLoopback(server.address.host) == isLoopback(url.host) ||
            server.address.host == url.host;
      }, orElse: () => null);
      if (server == null) return null;
      return server.urlToId(url);
    });
  }

  /// Determines if [sourcePath] is contained within any of the directories in
  /// the root package that are visible to this build environment.
  bool containsPath(String sourcePath) {
    var directories = ["lib"];
    directories.addAll(_directories.keys);
    return directories.any((dir) => path.isWithin(dir, sourcePath));
  }

  /// Pauses sending source asset updates to barback.
  void pauseUpdates() {
    // Cannot pause while already paused.
    assert(_modifiedSources == null);

    _modifiedSources = new Set<AssetId>();
  }

  /// Sends any pending source updates to barback and begins the asynchronous
  /// build process.
  void resumeUpdates() {
    // Cannot resume while not paused.
    assert(_modifiedSources != null);

    barback.updateSources(_modifiedSources);
    if (dartDevcEnvironment != null) {
      var modifiedPackages = new Set<String>()
        ..addAll(_modifiedSources.map((id) => id.package));
      modifiedPackages.forEach(dartDevcEnvironment.invalidatePackage);
    }
    _modifiedSources = null;
  }

  /// Loads the assets and transformers for this environment.
  ///
  /// This transforms and serves all library and asset files in all packages in
  /// the environment's package graph. It loads any transformer plugins defined
  /// in packages in [graph] and re-runs them as necessary when any input files
  /// change.
  ///
  /// If [Compiler.dart2JS], then the [Dart2JSTransformer] is implicitly
  /// added to end of the root package's transformer phases.
  ///
  /// If [entrypoints] is passed, only transformers necessary to run those
  /// entrypoints will be loaded.
  ///
  /// Returns a [Future] that completes once all inputs and transformers are
  /// loaded.
  Future _load({Iterable<AssetId> entrypoints}) {
    return log.progress("Initializing barback", () async {
      // Bind a server that we can use to load the transformers.
      var transformerServer = await BarbackServer.bind(this, _hostname, 0,
          dartDevcEnvironment: dartDevcEnvironment);

      var errorStream = barback.errors.map((error) {
        // Even most normally non-fatal barback errors should take down pub if
        // they happen during the initial load process.
        if (error is! AssetLoadException) throw error;

        log.error(log.red(error.message));
        log.fine(error.stackTrace.terse);
      });

      await _withStreamErrors(() {
        return log.progress("Loading source assets", _provideSources);
      }, [errorStream, barback.results]);

      log.fine("Provided sources.");

      errorStream = barback.errors.map((error) {
        // Now that we're loading transformers, errors they log shouldn't be
        // fatal, since we're starting to run them on real user assets which
        // may have e.g. syntax errors. If an error would cause a transformer
        // to fail to load, the load failure will cause us to exit.
        if (error is! TransformerException) throw error;

        var message = error.error.toString();
        if (error.stackTrace != null) {
          message += "\n" + error.stackTrace.terse.toString();
        }

        _log(new LogEntry(error.transform, error.transform.primaryId,
            LogLevel.ERROR, message, null));
      });

      await _withStreamErrors(() async {
        return log.progress("Loading transformers", () async {
          await loadAllTransformers(this, transformerServer,
              entrypoints: entrypoints);
          transformerServer.close();
        }, fine: true);
      }, [errorStream, barback.results, transformerServer.results]);
    }, fine: true);
  }

  /// Provides the public source assets in the environment to barback.
  ///
  /// If [watcherType] is not [WatcherType.NONE], enables watching on them.
  Future _provideSources() async {
    // Just include the "lib" directory from each package. We'll add the
    // other build directories in the root package by calling
    // [serveDirectory].
    await Future.wait(graph.packages.values.map((package) async {
      if (graph.isPackageStatic(package.name, compiler)) {
        return;
      }
      await _provideDirectorySources(package, "lib");
    }));
  }

  /// Provides all of the source assets within [dir] in [package] to barback.
  ///
  /// If [watcherType] is not [WatcherType.NONE], enables watching on them.
  /// Returns the subscription to the watcher, or `null` if none was created.
  Future<StreamSubscription<WatchEvent>> _provideDirectorySources(
      Package package, String dir) {
    log.fine("Providing sources for ${package.name}|$dir.");
    // TODO(rnystrom): Handle overlapping directories. If two served
    // directories overlap like so:
    //
    // $ pub serve example example/subdir
    //
    // Then the sources of the subdirectory will be updated and watched twice.
    // See: #17454
    if (_watcherType == WatcherType.NONE) {
      _updateDirectorySources(package, dir);
      return new Future.value();
    }

    // Watch the directory before listing is so we don't miss files that
    // are added between the initial list and registering the watcher.
    return _watchDirectorySources(package, dir).then((_) {
      _updateDirectorySources(package, dir);
    });
  }

  /// Updates barback with all of the files in [dir] inside [package].
  void _updateDirectorySources(Package package, String dir) {
    var ids = _listDirectorySources(package, dir);
    if (_modifiedSources == null) {
      barback.updateSources(ids);
      dartDevcEnvironment?.invalidatePackage(package.name);
    } else {
      _modifiedSources.addAll(ids);
    }
  }

  /// Removes all of the files in [dir] in the root package from barback.
  void _removeDirectorySources(String dir) {
    var ids = _listDirectorySources(rootPackage, dir);
    if (_modifiedSources == null) {
      barback.removeSources(ids);
      dartDevcEnvironment?.invalidatePackage(rootPackage.name);
    } else {
      _modifiedSources.removeAll(ids);
    }
  }

  /// Lists all of the source assets in [dir] inside [package].
  ///
  /// For large packages, listing the contents is a performance bottleneck, so
  /// this is optimized for our needs in here instead of using the more general
  /// but slower [listDir].
  Iterable<AssetId> _listDirectorySources(Package package, String dir) {
    // This is used in some performance-sensitive paths and can list many, many
    // files. As such, it leans more havily towards optimization as opposed to
    // readability than most code in pub. In particular, it avoids using the
    // path package, since re-parsing a path is very expensive relative to
    // string operations.
    return package.listFiles(beneath: dir).map((file) {
      // From profiling, path.relative here is just as fast as a raw substring
      // and is correct in the case where package.dir has a trailing slash.
      var relative = package.relative(file);

      if (Platform.operatingSystem == 'windows') {
        relative = relative.replaceAll("\\", "/");
      }

      var uri = new Uri(pathSegments: relative.split("/"));
      return new AssetId(package.name, uri.toString());
    });
  }

  /// Adds a file watcher for [dir] within [package], if the directory exists
  /// and the package needs watching.
  Future<StreamSubscription<WatchEvent>> _watchDirectorySources(
      Package package, String dir) {
    // If this package comes from a cached source, its contents won't change so
    // we don't need to monitor it. `packageId` will be null for the
    // application package, since that's not locked.
    var packageId = graph.lockFile.packages[package.name];
    if (packageId != null &&
        graph.entrypoint.cache.source(packageId.source) is CachedSource) {
      return new Future.value();
    }

    var subdirectory = package.path(dir);
    if (!dirExists(subdirectory)) return new Future.value();

    // TODO(nweiz): close this watcher when [barback] is closed.
    var watcher = _watcherType.create(subdirectory);
    var subscription = watcher.events.listen((event) {
      // Don't watch files symlinked into these directories.
      // TODO(rnystrom): If pub gets rid of symlinks, remove this.
      var parts = path.split(event.path);
      if (parts.contains("packages")) return;

      // Skip files that were (most likely) compiled from nearby ".dart"
      // files. These are created by the Editor's "Run as JavaScript"
      // command and are written directly into the package's directory.
      // When pub's dart2js transformer then tries to create the same file
      // name, we get a build error. To avoid that, just don't consider
      // that file to be a source.
      // TODO(rnystrom): Remove these when the Editor no longer generates
      // .js files and users have had enough time that they no longer have
      // these files laying around. See #15859.
      if (event.path.endsWith(".dart.js")) return;
      if (event.path.endsWith(".dart.js.map")) return;
      if (event.path.endsWith(".dart.precompiled.js")) return;

      var idPath = package.relative(event.path);
      var id = new AssetId(package.name, path.toUri(idPath).toString());
      if (event.type == ChangeType.REMOVE) {
        if (_modifiedSources != null) {
          _modifiedSources.remove(id);
        } else {
          barback.removeSources([id]);
          dartDevcEnvironment?.invalidatePackage(package.name);
        }
      } else if (_modifiedSources != null) {
        _modifiedSources.add(id);
      } else {
        barback.updateSources([id]);
        dartDevcEnvironment?.invalidatePackage(package.name);
      }
    });

    return watcher.ready.then((_) => subscription);
  }

  /// Returns the result of [futureCallback] unless any stream in [streams]
  /// emits an error before it's done.
  ///
  /// If a stream does emit an error, that error is thrown instead.
  /// [futureCallback] is a callback rather than a plain future to ensure that
  /// [streams] are listened to before any code that might cause an error starts
  /// running.
  Future _withStreamErrors(Future futureCallback(), List<Stream> streams) {
    var completer = new Completer.sync();
    var subscriptions = streams
        .map(
            (stream) => stream.listen((_) {}, onError: completer.completeError))
        .toList();

    new Future.sync(futureCallback).then((_) {
      if (!completer.isCompleted) completer.complete();
    }).catchError((error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });

    return completer.future.whenComplete(() {
      for (var subscription in subscriptions) {
        subscription.cancel();
      }
    });
  }
}

/// Log [entry] using Pub's logging infrastructure.
///
/// Since both [LogEntry] objects and the message itself often redundantly
/// show the same context like the file where an error occurred, this tries
/// to avoid showing redundant data in the entry.
void _log(LogEntry entry) {
  messageMentions(text) =>
      entry.message.toLowerCase().contains(text.toLowerCase());

  messageMentionsAsset(id) =>
      messageMentions(id.toString()) ||
      messageMentions(path.fromUri(entry.assetId.path));

  var prefixParts = [];

  // Show the level (unless the message mentions it).
  if (!messageMentions(entry.level.name)) {
    prefixParts.add("${entry.level} from");
  }

  // Show the transformer.
  prefixParts.add(entry.transform.transformer);

  // Mention the primary input of the transform unless the message seems to.
  if (!messageMentionsAsset(entry.transform.primaryId)) {
    prefixParts.add("on ${entry.transform.primaryId}");
  }

  // If the relevant asset isn't the primary input, mention it unless the
  // message already does.
  if (entry.assetId != entry.transform.primaryId &&
      !messageMentionsAsset(entry.assetId)) {
    prefixParts.add("with input ${entry.assetId}");
  }

  var prefix = "[${prefixParts.join(' ')}]:";
  var message = entry.message;
  if (entry.span != null) {
    message = entry.span.message(entry.message);
  }

  switch (entry.level) {
    case LogLevel.ERROR:
      log.error("${log.red(prefix)}\n$message");
      break;

    case LogLevel.WARNING:
      log.warning("${log.yellow(prefix)}\n$message");
      break;

    case LogLevel.INFO:
      log.message("${log.cyan(prefix)}\n$message");
      break;

    case LogLevel.FINE:
      log.fine("${log.gray(prefix)}\n$message");
      break;
  }
}

/// Exception thrown when trying to serve a new directory that overlaps one or
/// more directories already being served.
class OverlappingSourceDirectoryException implements Exception {
  /// The relative paths of the directories that overlap the one that could not
  /// be served.
  final List<String> overlappingDirectories;

  OverlappingSourceDirectoryException(this.overlappingDirectories);
}

/// An enum describing different modes of constructing a [DirectoryWatcher].
abstract class WatcherType {
  /// A watcher that automatically chooses its type based on the operating
  /// system.
  static const AUTO = const _AutoWatcherType();

  /// A watcher that always polls the filesystem for changes.
  static const POLLING = const _PollingWatcherType();

  /// No directory watcher at all.
  static const NONE = const _NoneWatcherType();

  /// Creates a new DirectoryWatcher.
  DirectoryWatcher create(String directory);

  String toString();
}

class _AutoWatcherType implements WatcherType {
  const _AutoWatcherType();

  DirectoryWatcher create(String directory) => new DirectoryWatcher(directory);

  String toString() => "auto";
}

class _PollingWatcherType implements WatcherType {
  const _PollingWatcherType();

  DirectoryWatcher create(String directory) =>
      new PollingDirectoryWatcher(directory);

  String toString() => "polling";
}

class _NoneWatcherType implements WatcherType {
  const _NoneWatcherType();

  DirectoryWatcher create(String directory) => null;

  String toString() => "none";
}
