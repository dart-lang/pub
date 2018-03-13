// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:analyzer/analyzer.dart';
import 'package:async/async.dart';
import 'package:barback/barback.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import 'package:compiler_unsupported/compiler.dart' as compiler;
import 'package:compiler_unsupported/src/dart2js.dart' show AbortLeg;
import 'package:compiler_unsupported/src/io/source_file.dart';
import '../barback.dart';
import '../dart.dart' as dart;
import '../utils.dart';
import 'asset_environment.dart';

/// The set of all valid configuration options for this transformer.
final _validOptions = new Set<String>.from([
  'commandLineOptions',
  'checked',
  'csp',
  'minify',
  'verbose',
  'environment',
  'preserveUris',
  'suppressWarnings',
  'suppressHints',
  'suppressPackageWarnings',
  'terse',
  'sourceMaps'
]);

/// A [Transformer] that uses dart2js's library API to transform Dart
/// entrypoints in "web" to JavaScript.
class Dart2JSTransformer extends Transformer implements LazyTransformer {
  /// We use this to ensure that only one compilation is in progress at a time.
  ///
  /// Dart2js uses lots of memory, so if we try to actually run compiles in
  /// parallel, it takes down the VM. The tracking bug to do something better
  /// is here: https://code.google.com/p/dart/issues/detail?id=14730.
  static final _pool = new Pool(1);

  final AssetEnvironment _environment;
  final BarbackSettings _settings;

  /// Whether source maps should be generated for the compiled JS.
  bool get _generateSourceMaps => _configBool('sourceMaps',
      defaultsTo: _settings.mode != BarbackMode.RELEASE);

  Dart2JSTransformer.withSettings(this._environment, this._settings) {
    var invalidOptions =
        _settings.configuration.keys.toSet().difference(_validOptions);
    if (invalidOptions.isEmpty) return;

    throw new FormatException("Unrecognized dart2js "
        "${pluralize('option', invalidOptions.length)} "
        "${toSentence(invalidOptions.map((option) => '"$option"'))}.");
  }

  Dart2JSTransformer(AssetEnvironment environment, BarbackMode mode)
      : this.withSettings(environment, new BarbackSettings({}, mode));

  /// Only ".dart" entrypoint files within a buildable directory are processed.
  bool isPrimary(AssetId id) {
    if (id.extension != ".dart") return false;

    // "lib" should only contain libraries. For efficiency's sake, we don't
    // look for entrypoints in there.
    return !id.path.startsWith("lib/");
  }

  Future apply(Transform transform) {
    // TODO(nweiz): If/when barback starts reporting what assets were modified,
    // don't re-run the entrypoint detection logic unless the primary input was
    // actually modified. See issue 16817.
    return _isEntrypoint(transform.primaryInput).then((isEntrypoint) {
      if (!isEntrypoint) return null;

      // Wait for any ongoing apply to finish first.
      return _pool.withResource(() {
        transform.logger.info("Compiling ${transform.primaryInput.id}...");
        var stopwatch = new Stopwatch()..start();
        return _doCompilation(transform).then((_) {
          stopwatch.stop();
          transform.logger.info("Took ${stopwatch.elapsed} to compile "
              "${transform.primaryInput.id}.");
        });
      });
    });
  }

  void declareOutputs(DeclaringTransform transform) {
    var primaryId = transform.primaryId;
    transform.declareOutput(primaryId.addExtension(".js"));
    if (_generateSourceMaps) {
      transform.declareOutput(primaryId.addExtension(".js.map"));
    }
  }

  /// Returns whether or not [asset] might be an entrypoint.
  Future<bool> _isEntrypoint(Asset asset) {
    return asset.readAsString().then((code) {
      try {
        var name = asset.id.path;
        if (asset.id.package != _environment.rootPackage.name) {
          name += " in ${asset.id.package}";
        }

        var parsed = parseCompilationUnit(code, name: name);
        return dart.isEntrypoint(parsed);
      } on AnalyzerErrorGroup {
        // If we get a parse error, consider the asset primary so we report
        // dart2js's more detailed error message instead.
        return true;
      }
    });
  }

  /// Run the dart2js compiler.
  Future _doCompilation(Transform transform) {
    var provider = new _BarbackCompilerProvider(_environment, transform,
        generateSourceMaps: _generateSourceMaps);

    // Create a "path" to the entrypoint script. The entrypoint may not actually
    // be on disk, but this gives dart2js a root to resolve relative paths
    // against.
    var id = transform.primaryInput.id;

    var entrypoint = _environment.graph.packages[id.package].path(id.path);

    // We define the packageRoot in terms of the entrypoint directory, and not
    // the rootPackage, to ensure that the generated source-maps are valid.
    // Source-maps contain relative URLs to package sources and these relative
    // URLs should be self-contained within the paths served by pub-serve.
    // See #1511 for details.
    var buildDir = _environment.getSourceDirectoryContaining(id.path);
    var packageRoot = _environment.rootPackage.path(buildDir, "packages");

    // TODO(rnystrom): Should have more sophisticated error-handling here. Need
    // to report compile errors to the user in an easily visible way. Need to
    // make sure paths in errors are mapped to the original source path so they
    // can understand them.
    return dart.compile(entrypoint, provider,
        commandLineOptions: _configCommandLineOptions,
        csp: _configBool('csp'),
        checked: _configBool('checked'),
        minify: _configBool('minify',
            defaultsTo: _settings.mode == BarbackMode.RELEASE),
        verbose: _configBool('verbose'),
        environment: _configEnvironment,
        packageRoot: packageRoot,
        analyzeAll: _configBool('analyzeAll'),
        preserveUris: _configBool('preserveUris'),
        suppressWarnings: _configBool('suppressWarnings'),
        suppressHints: _configBool('suppressHints'),
        suppressPackageWarnings:
            _configBool('suppressPackageWarnings', defaultsTo: true),
        terse: _configBool('terse'),
        includeSourceMapUrls: _generateSourceMaps,
        platformBinaries: provider.libraryRoot.resolve('lib/_internal/').path);
  }

  /// Parses and returns the "commandLineOptions" configuration option.
  List<String> get _configCommandLineOptions {
    if (!_settings.configuration.containsKey('commandLineOptions')) return null;

    var options = _settings.configuration['commandLineOptions'];
    if (options is List && options.every((option) => option is String)) {
      return DelegatingList.typed(options);
    }

    throw new FormatException('Invalid value for '
        '\$dart2js.commandLineOptions: ${JSON.encode(options)} (expected list '
        'of strings).');
  }

  /// Parses and returns the "environment" configuration option.
  Map<String, String> get _configEnvironment {
    if (!_settings.configuration.containsKey('environment')) {
      return _environment.environmentConstants;
    }

    var environment = _settings.configuration['environment'];
    if (environment is Map &&
        environment.keys.every((key) => key is String) &&
        environment.values.every((key) => key is String)) {
      return mergeMaps(
          DelegatingMap.typed(environment), _environment.environmentConstants);
    }

    throw new FormatException('Invalid value for \$dart2js.environment: '
        '${JSON.encode(environment)} (expected map from strings to strings).');
  }

  /// Parses and returns a boolean configuration option.
  ///
  /// [defaultsTo] is the default value of the option.
  bool _configBool(String name, {bool defaultsTo: false}) {
    if (!_settings.configuration.containsKey(name)) return defaultsTo;
    var value = _settings.configuration[name];
    if (value is bool) return value;
    throw new FormatException('Invalid value for \$dart2js.$name: '
        '${JSON.encode(value)} (expected true or false).');
  }
}

/// Defines an interface for dart2js to communicate with barback and pub.
///
/// Note that most of the implementation of diagnostic handling here was
/// copied from [FormattingDiagnosticHandler] in dart2js. The primary
/// difference is that it uses barback's logging code and, more importantly, it
/// handles missing source files more gracefully.
class _BarbackCompilerProvider implements dart.CompilerProvider {
  Uri get libraryRoot =>
      Uri.parse("${p.toUri(p.normalize(p.absolute(_libraryRootPath)))}/");

  final AssetEnvironment _environment;
  final Transform _transform;
  String _libraryRootPath;

  /// The map of previously loaded files.
  ///
  /// Used to show where an error occurred in a source file.
  final _sourceFiles = new Map<String, SourceFile>();

  // TODO(rnystrom): Make these configurable.
  /// Whether or not warnings should be logged.
  var _showWarnings = true;

  /// Whether or not hints should be logged.
  var _showHints = true;

  /// Whether or not verbose info messages should be logged.
  var _verbose = false;

  /// Whether an exception should be thrown on an error to stop compilation.
  final _throwOnError = false;

  /// This gets set after a fatal error is reported to quash any subsequent
  /// errors.
  var _isAborting = false;

  final bool generateSourceMaps;

  compiler.Diagnostic _lastKind;

  static final int _FATAL =
      compiler.Diagnostic.CRASH.ordinal | compiler.Diagnostic.ERROR.ordinal;
  static final int _INFO = compiler.Diagnostic.INFO.ordinal |
      compiler.Diagnostic.VERBOSE_INFO.ordinal;

  _BarbackCompilerProvider(this._environment, this._transform,
      {this.generateSourceMaps: true}) {
    // Dart2js outputs source maps that reference the Dart SDK sources. For
    // that to work, those sources need to be inside the build environment. We
    // do that by placing them in a special "$sdk" pseudo-package. In order for
    // dart2js to generate the right URLs to point to that package, we give it
    // a library root that corresponds to where that package can be found
    // relative to the public source directory containing that entrypoint.
    //
    // For example, say the package being compiled is "/dev/myapp", the
    // entrypoint is "web/sub/foo/bar.dart", and the source directory is
    // "web/sub". This means the SDK sources will be (conceptually) at:
    //
    //     /dev/myapp/web/sub/packages/$sdk/lib/
    //
    // This implies that the asset path for a file in the SDK is:
    //
    //     $sdk|lib/lib/...
    //
    // TODO(rnystrom): Fix this if #17751 is fixed.
    var buildDir = _environment
        .getSourceDirectoryContaining(_transform.primaryInput.id.path);
    _libraryRootPath =
        _environment.rootPackage.path(buildDir, "packages", r"$sdk");
  }

  /// A [CompilerInputProvider] for dart2js.
  Future /* <String | List<int>> */ provideInput(Uri resourceUri) {
    // We only expect to get absolute "file:" URLs from dart2js.
    assert(resourceUri.isAbsolute);
    assert(resourceUri.scheme == "file");

    var sourcePath = p.fromUri(resourceUri);
    return _readResource(resourceUri).then((source) {
      _sourceFiles[resourceUri.toString()] =
          new StringSourceFile(resourceUri, p.relative(sourcePath), source);
      return source;
    });
  }

  /// A [CompilerOutputProvider] for dart2js.
  EventSink<String> provideOutput(String name, String extension) {
    // TODO(rnystrom): Do this more cleanly. See: #17403.
    if (!generateSourceMaps && extension.endsWith(".map")) {
      return new NullSink<String>();
    }

    // TODO(nweiz): remove this special case when dart2js stops generating these
    // files.
    if (extension.endsWith(".precompiled.js")) return new NullSink<String>();

    var primaryId = _transform.primaryInput.id;

    // Dart2js uses an empty string for the name of the entrypoint library.
    // Otherwise, it's the name of a deferred library.
    var outPath;
    if (name == "") {
      outPath = _transform.primaryInput.id.path;
    } else {
      var dirname = p.url.dirname(_transform.primaryInput.id.path);
      outPath = p.url.join(dirname, name);
    }

    var id = new AssetId(primaryId.package, "$outPath.$extension");

    // Make a sink that dart2js can write to.
    var sink = new StreamController<String>();

    // dart2js gives us strings, but stream assets expect byte lists.
    var stream = UTF8.encoder.bind(sink.stream);

    // And give it to barback as a stream it can read from.
    _transform.addOutput(new Asset.fromStream(id, stream));

    return sink;
  }

  /// A [DiagnosticHandler] for dart2js, loosely based on
  /// [FormattingDiagnosticHandler].
  void handleDiagnostic(
      Uri uri, int begin, int end, String message, compiler.Diagnostic kind) {
    // TODO(ahe): Remove this when source map is handled differently.
    if (kind.name == "source map") return;

    if (_isAborting) return;
    _isAborting = (kind == compiler.Diagnostic.CRASH);

    var isInfo = (kind.ordinal & _INFO) != 0;
    if (isInfo && uri == null && kind != compiler.Diagnostic.INFO) {
      if (!_verbose && kind == compiler.Diagnostic.VERBOSE_INFO) return;
      _transform.logger.info(message);
      return;
    }

    // [_lastKind] records the previous non-INFO kind we saw.
    // This is used to suppress info about a warning when warnings are
    // suppressed, and similar for hints.
    if (kind != compiler.Diagnostic.INFO) _lastKind = kind;

    var logFn;
    if (kind == compiler.Diagnostic.ERROR) {
      logFn = _transform.logger.error;
    } else if (kind == compiler.Diagnostic.WARNING) {
      if (!_showWarnings) return;
      logFn = _transform.logger.warning;
    } else if (kind == compiler.Diagnostic.HINT) {
      if (!_showHints) return;
      logFn = _transform.logger.warning;
    } else if (kind == compiler.Diagnostic.CRASH) {
      logFn = _transform.logger.error;
    } else if (kind == compiler.Diagnostic.INFO) {
      if (_lastKind == compiler.Diagnostic.WARNING && !_showWarnings) return;
      if (_lastKind == compiler.Diagnostic.HINT && !_showHints) return;
      logFn = _transform.logger.info;
    } else {
      throw new Exception('Unknown kind: $kind (${kind.ordinal})');
    }

    var fatal = (kind.ordinal & _FATAL) != 0;
    if (uri == null) {
      logFn(message);
    } else {
      SourceFile file = _sourceFiles[uri.toString()];
      if (file == null) {
        // We got a message before loading the file, so just report the message
        // itself.
        logFn('$uri: $message');
      } else {
        logFn(file.getLocationMessage(message, begin, end));
      }
    }

    if (fatal && _throwOnError) {
      _isAborting = true;
      throw new AbortLeg(message);
    }
  }

  Future _readResource(Uri url) {
    return new Future.sync(() {
      // Find the corresponding asset in barback.
      var id = _sourceUrlToId(url);
      if (id != null) {
        if (id.extension == '.dill') {
          return collectBytes(_transform.readInput(id));
        } else {
          return _transform.readInputAsString(id);
        }
      }

      // Don't allow arbitrary file paths that point to things not in packages.
      // Doing so won't work in Dartium.
      throw new Exception(
          "Cannot read $url because it is outside of the build environment.");
    });
  }

  AssetId _sourceUrlToId(Uri url) {
    // See if it's a package path.
    var id = packagesUrlToId(url);
    if (id != null) return id;

    // See if it's a path to a "public" asset within the root package. All
    // other files in the root package are not visible to transformers, so
    // should be loaded directly from disk.
    var sourcePath = p.fromUri(url);
    if (_environment.containsPath(sourcePath)) {
      var relative =
          p.toUri(_environment.rootPackage.relative(sourcePath)).toString();

      return new AssetId(_environment.rootPackage.name, relative);
    }

    return null;
  }
}

/// An [EventSink] that discards all data. Provided to dart2js when we don't
/// want an actual output.
class NullSink<T> implements EventSink<T> {
  void add(T event) {}
  void addError(errorEvent, [StackTrace stackTrace]) {}
  void close() {}
}
