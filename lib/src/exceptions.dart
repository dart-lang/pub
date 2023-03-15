// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:source_span/source_span.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:yaml/yaml.dart';

import 'dart.dart';
import 'http.dart';

/// An exception class for exceptions that are intended to be seen by the user.
///
/// These exceptions won't have any debugging information printed when they're
/// thrown.
class ApplicationException implements Exception {
  final String message;

  ApplicationException(this.message);

  @override
  String toString() => message;
}

/// A subclass of [ApplicationException] that occurs when running a subprocess
/// has failed.
class RunProcessException extends ApplicationException {
  RunProcessException(String message) : super(message);
}

/// An exception class for exceptions that are intended to be seen by the user
/// and are associated with a problem in a file at some path.
class FileException implements ApplicationException {
  @override
  final String message;

  /// The path to the file that was missing or erroneous.
  final String path;

  FileException(this.message, this.path);

  @override
  String toString() => message;
}

/// A class for exceptions that wrap other exceptions.
class WrappedException extends ApplicationException {
  /// The underlying exception that [this] is wrapping, if any.
  final Object? innerError;

  /// The stack chain for [innerError] if it exists.
  final Chain? innerChain;

  WrappedException(String message, this.innerError, [StackTrace? innerTrace])
      : innerChain = innerTrace == null ? null : Chain.forTrace(innerTrace),
        super(message);
}

/// A class for exceptions that shouldn't be printed at the top level.
///
/// This is usually used when an exception has already been printed using
/// [log.exception].
class SilentException extends WrappedException {
  SilentException(Object? innerError, [StackTrace? innerTrace])
      : super(innerError.toString(), innerError, innerTrace);
}

/// A class for errors in a command's input data.
///
/// This corresponds to the `data` exit code.
class DataException extends ApplicationException {
  DataException(String message) : super(message);
}

/// An exception indicating that the users configuration is invalid.
///
/// This corresponds to the `config` exit code;
class ConfigException extends ApplicationException {
  ConfigException(String message) : super(message);
}

/// An class for exceptions where a package could not be found in a [Source].
///
/// The source is responsible for wrapping its internal exceptions in this so
/// that other code in pub can use this to show a more detailed explanation of
/// why the package was being requested.
class PackageNotFoundException extends WrappedException {
  /// A hint indicating an action the user could take to resolve this problem.
  ///
  /// This will be printed after the package resolution conflict.
  final String? hint;

  PackageNotFoundException(
    String message, {
    Object? innerError,
    StackTrace? innerTrace,
    this.hint,
  }) : super(message, innerError, innerTrace);

  @override
  String toString() => 'Package not available ($message).';
}

/// A class for exceptions where a package's checksum could not be validated.
class PackageIntegrityException extends PubHttpException {
  PackageIntegrityException(String message)
      : super(message, isIntermittent: true);
}

/// Returns whether [error] is a user-facing error object.
///
/// This includes both [ApplicationException] and any dart:io errors.
bool isUserFacingException(error) {
  return error is ApplicationException ||
      error is AnalyzerErrorGroup ||
      error is IsolateSpawnException ||
      error is IOException ||
      error is http.ClientException ||
      error is YamlException ||
      error is UsageException;
}

/// An exception thrown when parsing a `pubspec.yaml` or a `pubspec.lock`.
///
/// These exceptions are often thrown lazily while accessing pubspec properties.
///
/// By being an [ApplicationException] this will not trigger a stack-trace on
/// normal operations.
///
/// Works as a [SourceSpanFormatException], but can contain more context:
/// An optional [explanation] that explains the operation that failed.
/// An optional [hint] that gives suggestions how to proceed.
class SourceSpanApplicationException extends SourceSpanFormatException
    implements ApplicationException {
  final String? explanation;
  final String? hint;

  SourceSpanApplicationException(
    String message,
    SourceSpan? span, {
    this.hint,
    this.explanation,
  }) : super(message, span);

  @override
  String toString({color}) {
    return [
      if (explanation != null) explanation,
      span == null
          ? message
          : 'Error on ${span?.message(message, color: color)}',
      if (hint != null) hint,
    ].join('\n\n');
  }
}
