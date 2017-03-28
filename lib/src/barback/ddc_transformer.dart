// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;

typedef Future<bool> _InputChecker(AssetId id);
typedef Future<Asset> _InputGetter(AssetId id);
typedef Stream<List<int>> _InputReader(AssetId id);
typedef Future<String> _InputAsStringReader(AssetId id);
typedef void _OutputWriter(Asset);

/// Copies required resources into each entry point directory.
///
///  * Copies the `dart_sdk.js` file from the sdk into each entry point dir.
///  * Copies the `require.js` file from the sdk into each entry point dir, if
///    available.
class DevCompilerResourceTransformer extends AggregateTransformer
    implements LazyAggregateTransformer {
  @override
  // Group files by output directory.
  String classifyPrimary(AssetId id) {
    if (p.extension(id.path) != '.dart') return null;
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
    var sdkAmdJsPath =
        p.joinAll([sdk.path, 'lib', 'dev_compiler', 'amd', 'dart_sdk.js']);
    transform
        .addOutput(new Asset.fromFile(sdkJsOutputId, new File(sdkAmdJsPath)));

    // Copy the require.js file for AMD into the output folder, if it doesn't
    // exist already and does exist in the SDK, otherwise warn.
    var requireJsOutputId =
        new AssetId(transform.package, p.url.join(transform.key, 'require.js'));
    if (!await transform.hasInput(requireJsOutputId)) {
      var requireJsPath =
          p.joinAll([sdk.path, 'lib', 'dev_compiler', 'amd', 'require.js']);
      var requireJsFile = new File(requireJsPath);
      if (await requireJsFile.exists()) {
        transform
            .addOutput(new Asset.fromFile(requireJsOutputId, requireJsFile));
      } else {
        transform.logger.error(
            'Unable to locate `require.js` under the `${transform.key}` '
            'directory or the sdk. Either update your sdk to a version which '
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
class DevCompilerEntryPointModuleTransformer extends Transformer
    implements LazyTransformer {
  // Runs on all dart files not under `lib`.
  @override
  bool isPrimary(AssetId id) {
    if (id.extension != '.dart') return false;
    var dir = p.url.split(id.path).first;
    return dir != 'lib' && dir != 'bin';
  }

  @override
  Future apply(Transform transform) async {
    // Skip anything that isn't an entry point.
    if (!await _isEntryPoint(transform.primaryInput.id, transform.logger,
        transform.readInputAsString)) {
      return;
    }

    // The actual AMD module being created.
    var jsModuleId = transform.primaryInput.id.addExtension('.module.js');
    // The AMD bootstrap script, initializes the dart sdk, calls `require` with
    // the module for  `jsModuleId` and invokes its main.
    var bootstrapId = transform.primaryInput.id.addExtension('.bootstrap.js');
    // The entry point for the app, injects a deferred script tag whose src is
    // `require.js`, with the `data-main` attribute set to the `bootstrapId`
    // module.
    var entryPointId = transform.primaryInput.id.addExtension('.js');

    // Create the actual bootsrap.
    _createAmdBootstrap(
        entryPointId, bootstrapId, jsModuleId, transform.addOutput);

    // Find all transitive relative imports and compile them as a part of this
    // module.
    var idsToCompile = await _findRelativeIds(transform.primaryInput.id,
        transform.logger, transform.getInput, transform.hasInput);
    await _compileWithDDC(
      transform.logger,
      idsToCompile,
      transform.primaryInput.id.package,
      p.url.split(transform.primaryInput.id.path).first,
      transform.addOutput,
      transform.getInput,
      transform.hasInput,
      transform.readInput,
      jsModuleId,
      jsModuleId.addExtension('.map'),
      jsModuleId.changeExtension('.$_summaryExtension'),
      failOnError: true,
    );
  }

  @override
  void declareOutputs(DeclaringTransform transform) {
    transform.declareOutput(transform.primaryId.addExtension('.js'));
    transform.declareOutput(transform.primaryId.addExtension('.bootstrap.js'));
    transform.declareOutput(transform.primaryId.addExtension('.module.js'));
    transform.declareOutput(transform.primaryId.addExtension('.module.js.map'));
    transform.declareOutput(
        transform.primaryId.addExtension('.module.$_summaryExtension'));
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
        transform.logger,
        (await transform.primaryInputs.toList()).map((a) => a.id),
        transform.package,
        transform.key,
        transform.addOutput,
        transform.getInput,
        transform.hasInput,
        transform.readInput,
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

Future _compileWithDDC(
    TransformLogger logger,
    Iterable<AssetId> idsToCompile,
    String basePackage,
    String topLevelDir,
    _OutputWriter addOutput,
    _InputGetter getInput,
    _InputChecker hasInput,
    _InputReader readInput,
    AssetId jsOutputId,
    AssetId sourceMapOutputId,
    AssetId summaryOutputId,
    {bool failOnError = false}) async {
  var tmpDir = await Directory.systemTemp.createTemp();
  try {
    final watch = new Stopwatch()..start();
    final dependentPackages = await _findDependentPackages(
        basePackage, idsToCompile, logger, getInput, hasInput);
    logger.fine('Took ${watch.elapsed} to discover dependencies.');

    watch.reset();
    // Set up the packages directory in `tmpDir`.
    var packagesDir = new Directory(p.join(tmpDir.path, 'packages'));
    await packagesDir.create(recursive: true);
    var summaryIds = new Set<AssetId>();
    for (var package in dependentPackages) {
      // Don't try and read the summary that we are trying to output.
      if (package == basePackage && topLevelDir == 'lib') continue;
      summaryIds.addAll(_findSummaryIds(package));
    }

    // Copy all the summary files and Dart files into `tmpDir`.
    var summaryFiles = await _createTmpFiles(summaryIds, tmpDir, packagesDir,
        basePackage, hasInput, readInput, logger);
    var filesToCompile = await _createTmpFiles(idsToCompile, tmpDir,
        packagesDir, basePackage, hasInput, readInput, logger);
    logger.fine(
        'Took ${watch.elapsed} to set up a tmp environment for dartdevc.');

    var sdk = cli_util.getSdkDir();
    if (sdk == null) {
      logger.error('Unable to find dart sdk.');
      return;
    }

    watch.reset();
    logger.fine('Compiling package:$basePackage with dartdevc...');
    var sdk_summary = p.joinAll([sdk.path, 'lib', '_internal', 'ddc_sdk.sum']);
    var jsOutputFile = _fileForId(jsOutputId, tmpDir.path, packagesDir.path);
    var sourceMapOutputFile =
        _fileForId(sourceMapOutputId, tmpDir.path, packagesDir.path);
    var summaryOutputFile =
        _fileForId(summaryOutputId, tmpDir.path, packagesDir.path);
    var ddcArgs = <String>[
      '--dart-sdk-summary=${sdk_summary}',
      '--summary-extension=${_summaryExtension}',
      '--unsafe-angular2-whitelist',
      '--modules=amd',
      '--dart-sdk=${sdk.path}',
      '-o',
      jsOutputFile.path,
      '--module-root=${tmpDir.path}',
    ];
    if (topLevelDir == 'lib') {
      ddcArgs.add('--library-root=${p.join(packagesDir.path, basePackage)}');
    }
    for (var file in summaryFiles) {
      ddcArgs.addAll(['-s', file.path]);
    }
    ddcArgs.addAll(filesToCompile.map((f) => p
        .relative(f.path, from: tmpDir.path)
        .replaceFirst('packages/', 'package:')));
    var ddcPath = p.join(sdk.path, 'bin', 'dartdevc');
    var result =
        await Process.run(ddcPath, ddcArgs, workingDirectory: tmpDir.path);
    if (result.exitCode != 0) {
      var message = 'Failed to compile package:$basePackage with dartdevc '
          'after ${watch.elapsed}:\n\n${result.stdout}';
      failOnError ? logger.error(message) : logger.warning(message);
      return;
    } else {
      logger.info('Took ${watch.elapsed} to compile package:$basePackage '
          'with dartdevc.');
    }

    watch.reset();
    addOutput(
        new Asset.fromString(jsOutputId, await jsOutputFile.readAsString()));
    addOutput(new Asset.fromString(
        sourceMapOutputId, await sourceMapOutputFile.readAsString()));
    addOutput(new Asset.fromBytes(
        summaryOutputId, await summaryOutputFile.readAsBytes()));
    logger.fine(
        'Took ${watch.elapsed} to copy output files for package:$basePackage.');
  } catch (e) {
    logger.error('$e');
  } finally {
    await tmpDir.delete(recursive: true);
  }
}

void _createAmdBootstrap(AssetId entryPointId, AssetId bootstrapId,
    AssetId moduleId, _OutputWriter addOutput) {
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
  addOutput(new Asset.fromString(bootstrapId, bootstrapContent));

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
  addOutput(new Asset.fromString(entryPointId, entryPointContent));
}

/// Copies [ids] to [tmpDir], and returns the set of [File]s that were created.
Future<Set<File>> _createTmpFiles(
    Set<AssetId> ids,
    Directory tmpDir,
    Directory packagesDir,
    String basePackage,
    _InputChecker hasInput,
    _InputReader readInput,
    TransformLogger logger) async {
  var files = new Set<File>();
  await Future.wait(ids.map((id) async {
    if (!await hasInput(id)) {
      logger.warning('Unable to find asset `$id` when compiling '
          'package:$basePackage.');
      return;
    }
    var file = _fileForId(id, tmpDir.path, packagesDir.path);
    await _writeFile(file, readInput(id));
    files.add(file);
  }));
  return files;
}

/// Crawls from [entryId] and finds all [Asset]s that are relative through
/// relative uris (via all [UriBasedDirective]s).
Future<Set<AssetId>> _findRelativeIds(AssetId entryId, TransformLogger logger,
    _InputGetter getInput, _InputChecker hasInput,
    {Set<AssetId> foundIds}) async {
  foundIds ??= new Set<AssetId>();
  if (!await hasInput(entryId)) {
    logger.warning('Unable to find file `$entryId`.');
    return foundIds;
  }
  if (!foundIds.add(entryId)) return foundIds;

  var asset = await getInput(entryId);
  var contents = await asset.readAsString();
  var unit = parseDirectives(contents, name: '$entryId');

  var relativeIds = unit.directives
      .where((d) =>
          d is UriBasedDirective && !Uri.parse(d.uri.stringValue).isAbsolute)
      .map((d) => _urlToAssetId(
          asset.id, (d as UriBasedDirective).uri.stringValue, logger))
      .where((id) => id != null);
  for (var id in relativeIds) {
    await _findRelativeIds(id, logger, getInput, hasInput, foundIds: foundIds);
  }

  return foundIds;
}

/// Crawls from each of [assetIds] and finds all reachable packages (through
/// all [UriBasedDirective]s).
Future<Set<String>> _findDependentPackages(
    String basePackage,
    Iterable<AssetId> assetIds,
    TransformLogger logger,
    _InputGetter getInput,
    _InputChecker hasInput,
    {Set<AssetId> foundIds,
    Set<String> foundPackages}) async {
  foundIds ??= new Set<AssetId>();
  foundPackages ??= new Set<String>();
  for (var id in assetIds) {
    if (!foundIds.add(id)) continue;
    if (p.url.split(id.path).first == 'lib') foundPackages.add(id.package);

    if (!await hasInput(id)) {
      logger.warning(
          'Unable to find file `$id` when compiling package:$basePackage.');
      continue;
    }
    var asset = await getInput(id);
    var contents = await asset.readAsString();
    var unit = parseDirectives(contents, name: '$id');
    await _findDependentPackages(
        basePackage,
        unit.directives
            .where((d) => d is UriBasedDirective)
            .map((d) => _urlToAssetId(
                asset.id, (d as UriBasedDirective).uri.stringValue, logger))
            .where((id) => id != null),
        logger,
        getInput,
        hasInput,
        foundIds: foundIds,
        foundPackages: foundPackages);
  }
  return foundPackages;
}

File _fileForId(AssetId id, String rootDir, String packagesDir) {
  return p.url.split(id.path).first == 'lib'
      ? new File(p.joinAll(
          [packagesDir, id.package]..addAll(p.url.split(id.path).skip(1))))
      : new File(p.joinAll([rootDir]..addAll(p.url.split(id.path))));
}

Set<AssetId> _findSummaryIds(package) {
  // TODO(jakemac): Read build.yaml if available?
  return new Set<AssetId>()
    ..add(
        new AssetId(package, p.url.join('lib', '$package.$_summaryExtension')));
}

Future<bool> _isEntryPoint(
    AssetId id, TransformLogger logger, _InputAsStringReader readInputAsString,
    {Set<AssetId> seenIds}) async {
  seenIds ??= new Set<AssetId>();
  if (!seenIds.add(id)) return false;

  var content = await readInputAsString(id);
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
        id, (export as UriBasedDirective).uri.stringValue, logger);
    if (exportId == null) continue;
    if (await _isEntryPoint(exportId, logger, readInputAsString,
        seenIds: seenIds)) return true;
  }
  return false;
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

Future _writeFile(File file, Stream<List<int>> stream) async {
  await file.create(recursive: true);
  var sink = file.openWrite();
  await sink.addStream(stream);
  await sink.close();
}

const _summaryExtension = 'api.ds';
