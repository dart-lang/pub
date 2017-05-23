// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';

/// An [Exception] that is thrown when the analyzer fails to create a summary.
class AnalyzerSummaryException implements Exception {
  /// The module that couldn't be compiled.
  final AssetId assetId;

  /// The error response from the dartdevc worker.
  final String error;

  AnalyzerSummaryException(this.assetId, this.error);

  String toString() => 'Error creating summary for module: $assetId\n\n'
      '$error';
}

/// An [Exception] that is thrown when dartdevc compilation fails.
class DartDevcCompilationException implements Exception {
  /// The js module that couldn't be compiled.
  final AssetId assetId;

  /// The error response from the dartdevc worker.
  final String error;

  DartDevcCompilationException(this.assetId, this.error);

  String toString() => 'Error compiling dartdevc module: $assetId\n\n'
      '$error';
}

/// An [Exception] that is thrown when a module is not found for an [AssetId].
class MissingModuleException implements Exception {
  /// The asset that a module could not be found for.
  final AssetId assetId;

  MissingModuleException(this.assetId);

  String toString() => 'Unable to find module for $assetId';
}
