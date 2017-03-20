// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

typedef Future<Asset> _InputGetter(AssetId id);
typedef Stream<List<int>> _InputReader(AssetId id);
typedef void _OutputAdder(Asset);

class DevCompilerTransformer extends AggregateTransformer
    implements LazyAggregateTransformer {
  @override
  Future apply(AggregateTransform transform) async {
    await _compileWithDDC(
        transform.logger,
        (await transform.primaryInputs.toList()).map((a) => a.id),
        transform.package,
        transform.key,
        transform.addOutput,
        transform.getInput,
        transform.readInput);
  }

  @override
  String classifyPrimary(AssetId id) {
    if (!id.path.endsWith('.dart')) return null;
    var dir = p.url.split(id.path).first;
    if (dir != 'lib') return null;
    return dir;
  }

  @override
  void declareOutputs(DeclaringAggregateTransform transform) {
    transform.declareOutput(new AssetId(
        transform.package, '${transform.key}/${transform.package}.js'));
    transform.declareOutput(new AssetId(transform.package,
        '${transform.key}/${transform.package}.$_summaryExtension'));
  }
}

Future _compileWithDDC(
    TransformLogger logger,
    Iterable<AssetId> idsToCompile,
    String basePackage,
    String topLevelDir,
    _OutputAdder addOutput,
    _InputGetter getInput,
    _InputReader readInput) async {
  var tmpDir = await Directory.systemTemp.createTemp();
  final watch = new Stopwatch()..start();
  logger.info('Compiling package:$basePackage with dartdevc...');
  try {
    final stepWatch = new Stopwatch()..start();
    final dependentPackages =
        await findDependentPackages(idsToCompile, logger, getInput);
    logger.fine('Took ${stepWatch.elapsed} to discover dependencies.');

    stepWatch.reset();
    var packagesDir = new Directory(p.join(tmpDir.path, 'packages'));
    await packagesDir.createSync(recursive: true);
    var summaryIds = new Set<AssetId>();
    for (var package in dependentPackages) {
      if (package == basePackage && topLevelDir == 'lib') continue;
      summaryIds.addAll(_findSummaryIds(package));
    }

    var summaryFiles = new Set<File>();
    for (var id in summaryIds) {
      var file = id.path.startsWith('lib/')
          ? new File(p.joinAll([packagesDir.path, id.package]
            ..addAll(p.url.split(id.path).skip(1))))
          : new File(p.joinAll([tmpDir.path]..addAll(p.url.split(id.path))));
      await file.create(recursive: true);
      var sink = file.openWrite();
      await sink.addStream(readInput(id));
      await sink.close();
      summaryFiles.add(file);
    }

    var filesToCompile = new Set<File>();
    for (var id in idsToCompile) {
      var file = id.path.startsWith('lib/')
          ? new File(p.joinAll([packagesDir.path, id.package]
            ..addAll(p.url.split(id.path).skip(1))))
          : new File(
              p.joinAll([packagesDir.path]..addAll(p.url.split(id.path))));
      await file.create(recursive: true);
      var sink = file.openWrite();
      await sink.addStream(readInput(id));
      await sink.close();
      filesToCompile.add(file);
    }
    logger.fine(
        'Took ${stepWatch.elapsed} to set up a tmp environment for dartdevc.');

    var sdk = cli_util.getSdkDir();
    if (sdk == null) {
      logger.error('Unable to find dart sdk');
      return;
    }

    stepWatch.reset();
    var sdk_summary = p.joinAll([sdk.path, 'lib', '_internal', 'ddc_sdk.sum']);
    var jsOutputFile = new File(p.join(tmpDir.path, '$basePackage.js'));
    var summaryOutputFile =
        new File(p.join(tmpDir.path, '$basePackage.$_summaryExtension'));
    var ddcArgs = <String>[
      '--dart-sdk-summary=${sdk_summary}',
      '--summary-extension=${_summaryExtension}',
      '--unsafe-angular2-whitelist',
      '--modules=legacy',
      '--dart-sdk=${sdk.path}',
      '-o',
      jsOutputFile.path,
      '--module-root=${tmpDir.path}',
    ];
    if (topLevelDir == 'lib') {
      ddcArgs.add('--library-root=${p.join(packagesDir.path, topLevelDir)}');
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
    logger.fine('Took ${stepWatch.elapsed} to run dartdevc.');
    if (result.exitCode != 0) {
      logger.error(result.stdout);
      return;
    }

    addOutput(new Asset.fromString(
        new AssetId(basePackage, p.url.join(topLevelDir, '$basePackage.js')),
        await jsOutputFile.readAsString()));

    addOutput(new Asset.fromBytes(
        new AssetId(basePackage,
            p.url.join(topLevelDir, '$basePackage.$_summaryExtension')),
        await summaryOutputFile.readAsBytes()));

    logger.info('Took ${watch.elapsed} to compile package:$basePackage');
  } catch (e) {
    logger.error('$e');
  } finally {
    await tmpDir.delete(recursive: true);
  }
}

Future<Set<String>> findDependentPackages(
    Iterable<AssetId> assetIds, TransformLogger logger, _InputGetter getInput,
    {Set<String> foundPackages}) async {
  foundPackages ??= new Set<String>();
  for (var id in assetIds) {
    var asset = await getInput(id);
    if (!foundPackages.add(id.package)) continue;

    var contents = await asset.readAsString();
    var unit = parseDirectives(contents);
    await findDependentPackages(
        unit.directives
            .where((d) => d is UriBasedDirective)
            .map((d) => _urlToAssetId(
                asset.id, (d as UriBasedDirective).uri.stringValue, logger))
            .where((id) => id != null),
        logger,
        getInput,
        foundPackages: foundPackages);
  }
  return foundPackages;
}

Set<AssetId> _findSummaryIds(package) {
  // TODO(jakemac): Read build.yaml if available?
  return new Set<AssetId>()
    ..add(new AssetId(package, 'lib/$package.$_summaryExtension'));
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

const _summaryExtension = 'api.ds';
