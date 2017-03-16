// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

class DevCompilerTransformer extends AggregateTransformer
    implements LazyAggregateTransformer {
  @override
  Future apply(AggregateTransform transform) async {
    var tmpDir = await Directory.systemTemp.createTemp();
    final watch = new Stopwatch()..start();
    transform.logger.info('Compiling package:${transform.package} with DDC...');
    try {
      var dartAssets = await transform.primaryInputs.toList();
      assert(dartAssets.every((asset) => asset.id.extension == '.dart'));

      final dependentPackages = await findDependentPackages(
          dartAssets.map((asset) => asset.id), transform);

      var packagesDir = new Directory(p.join(tmpDir.path, 'packages'));
      await packagesDir.createSync(recursive: true);
      var summaryIds = new Set<AssetId>();
      for (var package in dependentPackages) {
        if (package == transform.package && transform.key == 'lib') continue;
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
        await sink.addStream(transform.readInput(id));
        await sink.close();
        summaryFiles.add(file);
      }

      var filesToCompile = new Set<File>();
      for (var asset in dartAssets) {
        var file = asset.id.path.startsWith('lib/')
            ? new File(p.joinAll([packagesDir.path, asset.id.package]
              ..addAll(p.url.split(asset.id.path).skip(1))))
            : new File(p.joinAll(
                [packagesDir.path]..addAll(p.url.split(asset.id.path))));
        await file.create(recursive: true);
        await file.writeAsString(await asset.readAsString());
        filesToCompile.add(file);
      }

      var sdk = cli_util.getSdkDir();
      if (sdk == null) {
        transform.logger.error('Unable to find dart sdk');
        return;
      }

      var sdk_summary =
          p.joinAll([sdk.path, 'lib', '_internal', 'ddc_sdk.sum']);
      var jsOutputFile =
          new File(p.join(tmpDir.path, '${transform.package}.js'));
      var summaryOutputFile = new File(
          p.join(tmpDir.path, '${transform.package}.$_summaryExtension'));
      var ddcArgs = <String>[
        '--dart-sdk-summary=${sdk_summary}',
        '--summary-extension=${_summaryExtension}',
        '--unsafe-angular2-whitelist',
        '--modules=legacy',
        '--dart-sdk=${sdk.path}',
        '-o',
        jsOutputFile.path,
        // '--library-root=${p.join(packagesDir.path, transform.package)}',
        '--module-root=${tmpDir.path}',
        '--package-root=${packagesDir.path}',
      ];
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
        transform.logger.error(result.stdout);
        return;
      }

      transform.addOutput(new Asset.fromString(
          new AssetId(
              transform.package, '${transform.key}/${transform.package}.js'),
          await jsOutputFile.readAsString()));

      transform.addOutput(new Asset.fromBytes(
          new AssetId(transform.package,
              '${transform.key}/${transform.package}.$_summaryExtension'),
          await summaryOutputFile.readAsBytes()));

      transform.logger.info(
          'Took ${watch.elapsed} to compile package:${transform.package}');
    } catch (e) {
      transform.logger.error('$e');
    } finally {
      await tmpDir.delete(recursive: true);
    }
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

Future<Set<String>> findDependentPackages(
    Iterable<AssetId> assetIds, AggregateTransform transform,
    {Set<String> foundPackages}) async {
  foundPackages ??= new Set<String>();
  for (var id in assetIds) {
    var asset = await transform.getInput(id);
    if (!foundPackages.add(id.package)) continue;

    var contents = await asset.readAsString();
    var unit = parseDirectives(contents);
    await findDependentPackages(
        unit.directives
            .where((d) => d is UriBasedDirective)
            .map((d) => _urlToAssetId(asset.id,
                (d as UriBasedDirective).uri.stringValue, transform.logger))
            .where((id) => id != null),
        transform,
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
