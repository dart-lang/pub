// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';

/// An [Exception] that is thrown when a worker returns an error.
abstract class _WorkerException implements Exception {
  final AssetId failedAsset;

  final String error;

  /// A message to prepend to [toString] output.
  String get message;

  _WorkerException(this.failedAsset, this.error);

  String toString() => '$message:$failedAsset\n\n$error';
}

/// An [Exception] that is thrown when the analyzer fails to create a summary.
class AnalyzerSummaryException extends _WorkerException {
  final String message = 'Error creating summary for module';

  AnalyzerSummaryException(AssetId summaryId, String error)
      : super(summaryId, error);
}

/// An [Exception] that is thrown when dartdevc compilation fails.
class DartDevcCompilationException extends _WorkerException {
  final String message = 'Error compiling dartdevc module';

  DartDevcCompilationException(AssetId jsId, String error) : super(jsId, error);
}

/// An [Exception] that is thrown when a module is not found for an [AssetId].
class MissingModuleException implements Exception {
  /// The asset that a module could not be found for.
  final AssetId assetId;

  MissingModuleException(this.assetId);

  String toString() => 'Unable to find module for $assetId';
}
