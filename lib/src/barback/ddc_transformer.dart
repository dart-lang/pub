// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

typedef Future<bool> _InputChecker(AssetId id);
typedef Future<Asset> _InputGetter(AssetId id);
typedef Stream<List<int>> _InputReader(AssetId id);
typedef void _OutputWriter(Asset);

class DevCompilerEntryPointTransformer extends Transformer
    implements LazyTransformer {
  // Runs on all dart files not under `lib`.
  @override
  bool isPrimary(AssetId id) =>
      id.extension == '.dart' && p.url.split(id.path).first != 'lib';

  @override
  Future apply(Transform transform) async {
    // First, check if we have a `main`.
    if (!await _isEntryPoint(transform.primaryInput.id, transform)) return;

    // Create the bootstrap script,
    var jsOutputId = transform.primaryInput.id.addExtension('.module.js');
    _createAmdBootstrap(transform.primaryInput.id.addExtension('.js'),
        jsOutputId, transform.addOutput);

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
      jsOutputId,
      jsOutputId.addExtension('.map'),
      jsOutputId.changeExtension('.$_summaryExtension'),
      failOnError: true,
    );
  }

  @override
  void declareOutputs(DeclaringTransform transform) {
    transform.declareOutput(transform.primaryId.addExtension('.js'));
  }
}

/// Compiles an entire package to a ddc module
class DevCompilerPackageTransformer extends AggregateTransformer
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
    var packagesDir = new Directory(p.join(tmpDir.path, 'packages'));
    await packagesDir.createSync(recursive: true);
    var summaryIds = new Set<AssetId>();
    for (var package in dependentPackages) {
      if (package == basePackage && topLevelDir == 'lib') continue;
      summaryIds.addAll(_findSummaryIds(package));
    }

    var summaryFiles = new Set<File>();
    for (var id in summaryIds) {
      if (!await hasInput(id)) {
        logger.warning('Unable to find summary file `$id` when compiling '
            'package:$basePackage.');
        continue;
      }
      var file = _fileForId(id, tmpDir.path, packagesDir.path);
      await _writeFile(file, readInput(id));
      summaryFiles.add(file);
    }

    var filesToCompile = new Set<File>();
    for (var id in idsToCompile) {
      if (!await hasInput(id)) {
        logger.warning(
            'Unable to find file `$id` when compiling package:$basePackage.');
        continue;
      }
      var file = _fileForId(id, tmpDir.path, packagesDir.path);
      await _writeFile(file, readInput(id));
      filesToCompile.add(file);
    }
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
    logger.info(
        'Took ${watch.elapsed} to compile package:$basePackage with dartdevc.');
    if (result.exitCode != 0) {
      if (failOnError) {
        logger.error(result.stdout);
      } else {
        logger.warning(result.stdout);
      }
      return;
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

void _createAmdBootstrap(
    AssetId bootstrapId, AssetId jsOutputId, _OutputWriter addOutput) {
  var appModuleName = p.withoutExtension(
      p.relative(jsOutputId.path, from: p.dirname(bootstrapId.path)));

  var jsOutputModule =
      jsOutputId.path.substring(0, jsOutputId.path.indexOf('.'));
  var appModuleScope = p.url.split(jsOutputModule).join("__");
  var bootstrapContent = '''
require(["$appModuleName", "dart_sdk"], function(app, dart_sdk) {
  dart_sdk._isolate_helper.startRootIsolate(() => {}, []);
  app.$appModuleScope.main();
});
''';
  addOutput(new Asset.fromString(bootstrapId, bootstrapContent));
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

Future<bool> _isEntryPoint(AssetId id, Transform transform,
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
    if (await _isEntryPoint(exportId, transform, seenIds: seenIds)) return true;
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
