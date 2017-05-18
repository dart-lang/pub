// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';

import '../compiler.dart';
import '../log.dart' as log;
import '../utils.dart';
import 'asset_environment.dart';
import 'barback_server.dart';
import 'dart2js_transformer.dart';
import 'excluding_transformer.dart';
import 'transformer_config.dart';
import 'transformer_id.dart';
import 'transformer_isolate.dart';

/// A class that loads transformers defined in specific files.
class TransformerLoader {
  final AssetEnvironment _environment;

  final BarbackServer _transformerServer;

  final _isolates = new Map<TransformerId, TransformerIsolate>();

  final _transformers = new Map<TransformerConfig, Set<Transformer>>();

  /// The packages that use each transformer id.
  ///
  /// Used for error reporting.
  final _transformerUsers = new Map<TransformerId, Set<String>>();

  TransformerLoader(this._environment, this._transformerServer) {
    for (var package in _environment.graph.packages.values) {
      for (var config in unionAll(package.pubspec.transformers)) {
        _transformerUsers
            .putIfAbsent(config.id, () => new Set<String>())
            .add(package.name);
      }
    }
  }

  /// Loads a transformer plugin isolate that imports the transformer libraries
  /// indicated by [ids].
  ///
  /// Once the returned future completes, transformer instances from this
  /// isolate can be created using [transformersFor] or [transformersForPhase].
  ///
  /// This skips any ids that have already been loaded.
  Future load(Iterable<TransformerId> ids, {String snapshot}) async {
    ids = ids.where((id) => !_isolates.containsKey(id)).toList();
    if (ids.isEmpty) return;

    var isolate = await log.progress(
        "Loading ${toSentence(ids)} transformers",
        () => TransformerIsolate.spawn(_environment, _transformerServer, ids,
            snapshot: snapshot));

    for (var id in ids) {
      _isolates[id] = isolate;
    }
  }

  /// Instantiates and returns all transformers in the library indicated by
  /// [config] with the given configuration.
  ///
  /// If this is called before the library has been loaded into an isolate via
  /// [load], it will return an empty set.
  Future<Set<Transformer>> transformersFor(TransformerConfig config) async {
    if (_transformers.containsKey(config)) return _transformers[config];

    if (_isolates.containsKey(config.id)) {
      var transformers = await _isolates[config.id].create(config);
      if (transformers.isNotEmpty) {
        _transformers[config] = transformers;
        return transformers;
      }

      var message = "No transformers";
      if (config.configuration.isNotEmpty) {
        message += " that accept configuration";
      }

      var location;
      if (config.id.path == null) {
        location = 'package:${config.id.package}/transformer.dart or '
            'package:${config.id.package}/${config.id.package}.dart';
      } else {
        location = 'package:$config.dart';
      }

      var users = toSentence(ordered(_transformerUsers[config.id]));
      fail("$message were defined in $location,\n"
          "required by $users.");
    } else if (config.id.package != '\$dart2js') {
      return new Future.value(new Set());
    }

    var transformer;
    try {
      if (_environment.compiler == Compiler.dart2JS) {
        transformer = new Dart2JSTransformer.withSettings(_environment,
            new BarbackSettings(config.configuration, _environment.mode));
        // Handle any exclusions.
        _transformers[config] =
            new Set.from([ExcludingTransformer.wrap(transformer, config)]);
      } else {
        // Empty set if dart2js is disabled based on compiler flag.
        _transformers[config] = new Set();
      }
    } on FormatException catch (error, stackTrace) {
      fail(error.message, error, stackTrace);
    }

    return _transformers[config];
  }

  /// Loads all [Transformer]s or [AggregateTransformer]s defined in each phase
  /// of [phases].
  ///
  /// If any library hasn't yet been loaded via [load], it will be ignored.
  Future<List<Set>> transformersForPhases(
      Iterable<Set<TransformerConfig>> phases) async {
    var result = await Future.wait(phases.map((phase) async {
      var transformers = await waitAndPrintErrors(phase.map(transformersFor));
      return unionAll(transformers);
    }));

    // Return a growable list so that callers can add phases.
    return result.toList();
  }
}
