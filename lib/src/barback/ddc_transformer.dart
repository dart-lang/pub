// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

import '../io.dart';

const _summaryExtension = 'api.ds';

/// Copies required resources into each entry point directory.
///
///  * Copies the `dart_sdk.js` file from the SDK into each entry point dir.
///  * Copies the `require.js` file from the SDK into each entry point dir, if
///    available.
class DevCompilerResourceTransformer extends AggregateTransformer
    implements LazyAggregateTransformer {
  @override
  // Group files by output directory.
  String classifyPrimary(AssetId id) {
    if (p.extension(id.path) != '.dart') return null;
    assert(id.path.isNotEmpty);
    var dir = p.url.split(id.path).first;
    if (dir == 'lib' || dir == 'bin') return null;
    return p.url.dirname(id.path);
  }

  @override
  Future apply(AggregateTransform transform) async {
    var sdk = cli_util.getSdkDir();

    // Copy the dart_sdk.js file for AMD into the output folder.
    var sdkJsOutputId = new AssetId(
        transform.package, p.url.join(transform.key, 'dart_sdk.js'));
    var sdkAmdJsPath = p.url.join(sdk.path, 'lib/dev_compiler/amd/dart_sdk.js');
    transform
        .addOutput(new Asset.fromFile(sdkJsOutputId, new File(sdkAmdJsPath)));

    // Copy the require.js file for AMD into the output folder, if it doesn't
    // exist already and does exist in the SDK, otherwise warn.
    var requireJsOutputId =
        new AssetId(transform.package, p.url.join(transform.key, 'require.js'));
    if (!await transform.hasInput(requireJsOutputId)) {
      var requireJsPath =
          p.url.join(sdk.path, 'lib/dev_compiler/amd/require.js');
      var requireJsFile = new File(requireJsPath);
      if (await requireJsFile.exists()) {
        transform
            .addOutput(new Asset.fromFile(requireJsOutputId, requireJsFile));
      } else {
        transform.logger.error(
            'Unable to locate `require.js` under the `${transform.key}` '
            'directory or the sdk. Either update your SDK to a version which '
            'contains that file or download your own copy and put it the '
            '`${transform.key}` directory under your package.');
      }
    }
  }

  @override
  Future declareOutputs(DeclaringAggregateTransform transform) async {
    transform.declareOutput(new AssetId(
        transform.package, p.url.join(transform.key, 'dart_sdk.js')));
    transform.declareOutput(new AssetId(
        transform.package, p.url.join(transform.key, 'require.js')));
  }
}

/// Compiles an entry point and all its relative imports under the same top
/// level directory into a single ddc module.
///
/// Also generates a script to bootstrap the app and invoke `main` from the
/// module that was created.
class DevCompilerEntrypointModuleTransformer extends Transformer
    implements LazyTransformer {
  /// Runs on all dart files not under "lib" or "bin".
  @override
  bool isPrimary(AssetId id) {
    if (id.extension != '.dart') return false;
    var dir = p.url.split(id.path).first;
    return dir != 'lib' && dir != 'bin';
  }

  @override
  Future apply(Transform transform) async {
    var dartId = transform.primaryInput.id;
    // Skip anything that isn't an entry point.
    if (!await _isEntrypoint(dartId, transform)) {
      return;
    }

    // The actual AMD module being created.
    var jsModuleId = dartId.addExtension('.module.js');
    // The AMD bootstrap script, initializes the dart SDK, calls `require` with
    // the module for  `jsModuleId` and invokes its main.
    var bootstrapId = dartId.addExtension('.bootstrap.js');
    // The entry point for the app, injects a deferred script tag whose src is
    // `require.js`, with the `data-main` attribute set to the `bootstrapId`
    // module.
    var entryPointId = dartId.addExtension('.js');

    // Create the actual bootsrap.
    _createAmdBootstrap(entryPointId, bootstrapId, jsModuleId, transform);

    // Find all transitive relative imports and compile them as a part of this
    // module.
    var idsToCompile = await _findRelativeIds(dartId, transform);
    await _compileWithDDC(
      idsToCompile,
      dartId.package,
      p.url.split(dartId.path).first,
      transform,
      jsModuleId,
      jsModuleId.addExtension('.map'),
      jsModuleId.changeExtension('.$_summaryExtension'),
      failOnError: true,
    );
  }

  @override
  void declareOutputs(DeclaringTransform transform) {
    var dartId = transform.primaryId;
    transform.declareOutput(dartId.addExtension('.js'));
    transform.declareOutput(dartId.addExtension('.bootstrap.js'));
    transform.declareOutput(dartId.addExtension('.module.js'));
    transform.declareOutput(dartId.addExtension('.module.js.map'));
    transform.declareOutput(dartId.addExtension('.module.$_summaryExtension'));
  }
}

/// Compiles an entire package to a single ddc module.
class DevCompilerPackageModuleTransformer extends AggregateTransformer
    implements LazyAggregateTransformer {
  @override
  Future apply(AggregateTransform transform) async {
    var jsOutputId = new AssetId(
        transform.package, p.url.join('lib', '${transform.package}.js'));
    await _compileWithDDC(
        (await transform.primaryInputs.toList()).map((a) => a.id),
        transform.package,
        transform.key,
        new _WrappedTransform(transform),
        jsOutputId,
        jsOutputId.addExtension('.map'),
        jsOutputId.changeExtension('.$_summaryExtension'));
  }

  @override
  String classifyPrimary(AssetId id) {
    if (id.extension != '.dart') return null;
    var dir = p.url.split(id.path).first;
    if (dir != 'lib') return null;
    return dir;
  }

  @override
  void declareOutputs(DeclaringAggregateTransform transform) {
    transform.declareOutput(new AssetId(
        transform.package, p.url.join('lib', '${transform.package}.js')));
    transform.declareOutput(new AssetId(
        transform.package, p.url.join('lib', '${transform.package}.js.map')));
    transform.declareOutput(new AssetId(transform.package,
        p.url.join('lib', '${transform.package}.$_summaryExtension')));
  }
}

/// [AggregateTransform] that is wrapped to pretend it is an [Transform].
class _WrappedTransform implements Transform {
  final AggregateTransform _transform;

  _WrappedTransform(this._transform);

  // Unsupported members
  void consumePrimary() => throw new UnsupportedError(
      "An AggregateTransform wrapped as a Transform doesn't have a single "
      "primary input to consume.");
  Asset get primaryInput => throw new UnsupportedError(
      "An AggregateTransform wrapped as a Transform doesn't have a single "
      "primary input to return.");

  // Forwarding members
  TransformLogger get logger => _transform.logger;
  void addOutput(Asset asset) => _transform.addOutput(asset);
  Future<Asset> getInput(AssetId id) => _transform.getInput(id);
  Future<bool> hasInput(AssetId id) => _transform.hasInput(id);
  Stream<List<int>> readInput(AssetId id) => _transform.readInput(id);
  Future<String> readInputAsString(AssetId id, {Encoding encoding}) =>
      _transform.readInputAsString(id, encoding: encoding ?? UTF8);
}

/// Compiles [idsToCompile] into a single module, using the `dartdevc` binary
/// from the SDK.
///
/// The [basePackage] is the package currently being compiled, and [topLevelDir]
/// is the directory under that package that is being compiled. All
/// [idsToCompile] must live under that directory and package.
///
/// The [jsOutputId], [sourceMapOutputId], and [summaryOutputId] are the assets
/// to output for the module.
///
/// If [failOnError] is true, then an error will be logged if compilation fails,
/// otherwise only a warning will be logged. This is because during a
/// `pub build` it is ok for certain packages to fail to compile if they aren't
/// imported by the entry points. It is only if an entry point fails that we
/// should actually fail the build (and it will fail if any module it depends on
/// failed).
///
// TODO(jakemac53): Investigate other ways of running dartdevc and compare
// performance, https://github.com/dart-lang/pub/issues/1551.
Future _compileWithDDC(
    Iterable<AssetId> idsToCompile,
    String basePackage,
    String topLevelDir,
    Transform transform,
    AssetId jsOutputId,
    AssetId sourceMapOutputId,
    AssetId summaryOutputId,
    {bool failOnError = false}) async {
  var logger = transform.logger;
  var logError = failOnError ? logger.error : logger.warning;

  // Validate that `idsToCompile`, `basePackage`, and `topLevelDir` all agree
  // with each other.
  var invalidIdsToCompile = idsToCompile.where((id) {
    assert(id.path.isNotEmpty);
    return id.package != basePackage ||
        p.url.split(id.path).first != topLevelDir;
  });
  if (invalidIdsToCompile.isNotEmpty) {
    logError('Invalid dartdevc module, all files must be under the '
        '`$topLevelDir` directory of the `$basePackage` package.\n'
        'Got the following invalid files:\n'
        '${invalidIdsToCompile.join('\n')}');
  }

  var tempDir = await Directory.systemTemp.createTemp();
  try {
    var watch = new Stopwatch()..start();
    var dependentPackages =
        await _findDependentPackages(basePackage, idsToCompile, transform);
    logger.fine('Took ${watch.elapsed} to discover dependencies.');

    watch.reset();
    // Set up the packages directory in `tempDir`.
    var packagesDir = new Directory(p.join(tempDir.path, 'packages'));
    await packagesDir.create(recursive: true);
    var summaryIds = new Set<AssetId>();
    for (var package in dependentPackages) {
      // Don't try and read the summary that we are trying to output.
      if (package == basePackage && topLevelDir == 'lib') continue;
      summaryIds.addAll(_findSummaryIds(package));
    }

    // Copy all the summary files and Dart files into `tempDir`.
    var summaryFiles = await _createTempFiles(
        summaryIds, tempDir, packagesDir, basePackage, transform);
    var filesToCompile = await _createTempFiles(
        idsToCompile, tempDir, packagesDir, basePackage, transform);
    logger.fine(
        'Took ${watch.elapsed} to set up a temp environment for dartdevc.');

    var sdk = cli_util.getSdkDir();
    if (sdk == null) {
      logger.error('Unable to find dart sdk.');
      return;
    }

    watch.reset();
    logger.fine('Compiling package:$basePackage with dartdevc...');
    var sdk_summary = p.url.join(sdk.path, 'lib/_internal/ddc_sdk.sum');
    var jsOutputFile = _fileForId(jsOutputId, tempDir.path, packagesDir.path);
    var sourceMapOutputFile =
        _fileForId(sourceMapOutputId, tempDir.path, packagesDir.path);
    var summaryOutputFile =
        _fileForId(summaryOutputId, tempDir.path, packagesDir.path);
    var ddcArgs = [
      '--dart-sdk-summary=$sdk_summary',
      '--summary-extension=$_summaryExtension',
      // TODO(jakemac53): Remove when no longer needed.
      '--unsafe-angular2-whitelist',
      '--modules=amd',
      '--dart-sdk=${sdk.path}',
      '-o',
      jsOutputFile.path,
      '--module-root=${tempDir.path}',
    ];
    if (topLevelDir == 'lib') {
      ddcArgs.add('--library-root=${p.join(packagesDir.path, basePackage)}');
    }
    for (var file in summaryFiles) {
      ddcArgs.addAll(['-s', file.path]);
    }
    ddcArgs.addAll(filesToCompile.map((f) => p
        .relative(f.path, from: tempDir.path)
        .replaceFirst('packages/', 'package:')));
    var ddcPath = p.join(sdk.path, 'bin', 'dartdevc');
    var result = await runProcess(ddcPath, ddcArgs, workingDir: tempDir.path);
    if (result.exitCode != 0) {
      logError('Failed to compile package:$basePackage with dartdevc '
          'after ${watch.elapsed}:\n\n${result.stdout.join('\n')}');
      return;
    } else {
      logger.info('Took ${watch.elapsed} to compile package:$basePackage '
          'with dartdevc.');
    }

    watch.reset();
    transform.addOutput(
        new Asset.fromString(jsOutputId, await jsOutputFile.readAsString()));
    transform.addOutput(new Asset.fromString(
        sourceMapOutputId, await sourceMapOutputFile.readAsString()));
    transform.addOutput(new Asset.fromBytes(
        summaryOutputId, await summaryOutputFile.readAsBytes()));
    logger.fine('Took ${watch.elapsed} to produce output assets for '
        'package:$basePackage.');
  } finally {
    await tempDir.delete(recursive: true);
  }
}

/// Bootstraps the entry point [moduleId] with two additional files.
///
/// The [entryPointId] is the entry point for the app, it simply injects a
/// script tag whose src is `require.js` and whose `data-main` points at the
/// [bootstrapId].
///
/// The [bootstrapId] requires [moduleId] and invokes its top level `main`,
/// after performing some necessary SDK setup.
void _createAmdBootstrap(AssetId entryPointId, AssetId bootstrapId,
    AssetId moduleId, Transform transform) {
  var appModuleName = p.withoutExtension(
      p.relative(moduleId.path, from: p.dirname(entryPointId.path)));

  // TODO(jakemac53): Sane module name creation, this only works in the most
  // basic of cases.
  //
  // See https://github.com/dart-lang/sdk/issues/27262 for the root issue which
  // will allow us to not rely on the naming schemes that dartdevc uses
  // internally, but instead specify our own.
  var appModuleScope = p.url
      .split(moduleId.path.substring(0, moduleId.path.indexOf('.dart')))
      .join("__");
  var bootstrapContent = '''
require(["$appModuleName", "dart_sdk"], function(app, dart_sdk) {
  dart_sdk._isolate_helper.startRootIsolate(() => {}, []);
  app.$appModuleScope.main();
});
''';
  transform.addOutput(new Asset.fromString(bootstrapId, bootstrapContent));

  var bootstrapModuleName = p.withoutExtension(
      p.relative(bootstrapId.path, from: p.dirname(entryPointId.path)));
  var entryPointContent = '''
var el = document.createElement("script");
el.defer = true;
el.async = false;
el.src = "require.js";
el.setAttribute("data-main", "$bootstrapModuleName");
document.head.appendChild(el);
''';
  transform.addOutput(new Asset.fromString(entryPointId, entryPointContent));
}

/// Copies [ids] to [tempDir], and returns the set of [File]s that were created.
Future<Iterable<File>> _createTempFiles(Set<AssetId> ids, Directory tempDir,
    Directory packagesDir, String basePackage, Transform transform) async {
  var files = <File>[];
  await Future.wait(ids.map((id) async {
    if (!await transform.hasInput(id)) {
      transform.logger.warning('Unable to find asset `$id` when compiling '
          'package:$basePackage.');
      return;
    }
    var file = _fileForId(id, tempDir.path, packagesDir.path);
    await createFileFromStream(transform.readInput(id), file.path,
        recursive: true);
    files.add(file);
  }));
  return files;
}

/// Crawls from [entryId] and finds all [Asset]s that are reachable through
/// relative URIs (via all [UriBasedDirective]s).
Future<Set<AssetId>> _findRelativeIds(AssetId entryId, Transform transform,
    {Set<AssetId> foundIds}) async {
  foundIds ??= new Set<AssetId>();
  if (!await transform.hasInput(entryId)) {
    transform.logger.warning('Unable to find file `$entryId`.');
    return foundIds;
  }
  if (!foundIds.add(entryId)) return foundIds;

  var relativeIds =
      await _directivesToIds(entryId, transform, relativeOnly: true);
  for (var id in relativeIds) {
    await _findRelativeIds(id, transform, foundIds: foundIds);
  }

  return foundIds;
}

/// Crawls from each of [assetIds] and finds all reachable packages (through
/// all [UriBasedDirective]s).
Future<Set<String>> _findDependentPackages(
    String basePackage, Iterable<AssetId> assetIds, Transform transform,
    {Set<AssetId> foundIds, Set<String> foundPackages}) async {
  foundIds ??= new Set<AssetId>();
  foundPackages ??= new Set<String>();
  for (var id in assetIds) {
    if (!foundIds.add(id)) continue;
    if (p.url.split(id.path).first == 'lib') foundPackages.add(id.package);

    if (!await transform.hasInput(id)) {
      transform.logger.warning(
          'Unable to find file `$id` when compiling package:$basePackage.');
      continue;
    }
    await _findDependentPackages(
        basePackage, await _directivesToIds(id, transform), transform,
        foundIds: foundIds, foundPackages: foundPackages);
  }
  return foundPackages;
}

File _fileForId(AssetId id, String rootDir, String packagesDir) {
  return p.url.split(id.path).first == 'lib'
      ? new File(p.joinAll(
          [packagesDir, id.package]..addAll(p.url.split(id.path).skip(1))))
      : new File(p.joinAll([rootDir]..addAll(p.url.split(id.path))));
}

/// Returns the [AssetId]s for the summaries of [package].
///
/// Today this is always just a single file under `lib`, but that will likely
/// change when we add support for multiple modules.
Iterable<AssetId> _findSummaryIds(String package) {
  // TODO(jakemac): Read build.yaml if available?
  return <AssetId>[
    new AssetId(package, p.url.join('lib', '$package.$_summaryExtension'))
  ];
}

Future<bool> _isEntrypoint(AssetId id, Transform transform,
    {Set<AssetId> seenIds}) async {
  seenIds ??= new Set<AssetId>();
  if (!seenIds.add(id)) return false;

  var content = await transform.readInputAsString(id);
  // Suppress errors at this step, dartdevc will error later if the file can't
  // parse.
  var unit = parseCompilationUnit(content, name: '$id', suppressErrors: true);
  // Logic to check for a valid main(). Currently this is a check for any
  // top level function called "main" with 2 or fewer parameters. The 2nd
  // argument is allowed for the isolate conversion test.
  if (unit.declarations.any((d) =>
      d is FunctionDeclaration &&
      d.name.name == 'main' &&
      d.functionExpression.parameters.parameters.length <= 2)) {
    return true;
  }

  // Additionally search all exports that might be exposing a `main` based on
  // the show/hide settings.
  var exportsToSearch = unit.directives.where((d) {
    if (d is! ExportDirective) return false;
    for (var combinator in (d as ExportDirective).combinators) {
      if ('${combinator.keyword}' == 'show') {
        if (combinator.childEntities.any((e) => '$e' == 'main')) return true;
      } else if ('${combinator.keyword}' == 'hide') {
        if (combinator.childEntities.any((e) => '$e' == 'main')) return false;
      }
    }
    return true;
  });

  for (var export in exportsToSearch) {
    var exportId = _urlToAssetId(
        id, (export as UriBasedDirective).uri.stringValue, transform.logger);
    if (exportId == null) continue;
    if (await _isEntrypoint(exportId, transform, seenIds: seenIds)) return true;
  }
  return false;
}

/// Reads and parses [sourceId], and returns an [Iterable<AssetId>] for all the
/// assets referred to by the [UriBasedDirective]s.
///
/// If [relativeOnly] then any `package:` directives will be ignored.
Future<Iterable<AssetId>> _directivesToIds(
    AssetId sourceId, Transform transform,
    {bool relativeOnly = false}) async {
  var contents = await transform.readInputAsString(sourceId);
  var unit = parseDirectives(contents, name: '$sourceId');
  Iterable<UriBasedDirective> uriDirectives =
      unit.directives.where((d) => d is UriBasedDirective);
  if (relativeOnly) {
    uriDirectives = uriDirectives
        .where((d) => Uri.parse(d.uri.stringValue).scheme != 'package');
  }
  return uriDirectives
      .map((d) => _urlToAssetId(sourceId, d.uri.stringValue, transform.logger))
      .where((id) => id != null);
}

AssetId _urlToAssetId(AssetId source, String url, TransformLogger logger) {
  var uri = Uri.parse(url);
  if (uri.isAbsolute) {
    if (uri.scheme == 'package') {
      var parts = uri.pathSegments;
      return new AssetId(
          parts.first, p.url.joinAll(['lib']..addAll(parts.skip(1))));
    } else if (uri.scheme == 'dart') {
      return null;
    } else {
      logger.error('Unable to resolve import. Only package: paths and relative '
          'paths are supported, got `$url`');
      return null;
    }
  } else {
    // Relative path.
    var targetPath =
        p.url.normalize(p.url.join(p.url.dirname(source.path), uri.path));
    return new AssetId(source.package, targetPath);
  }
}
