// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:stack_trace/stack_trace.dart';
import 'package:yaml/yaml.dart';

import 'dart.dart';
import 'sdk.dart';

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
  final Object innerError;

  /// The stack chain for [innerError] if it exists.
  final Chain innerChain;

  WrappedException(String message, this.innerError, [StackTrace innerTrace])
      : innerChain = innerTrace == null ? null : Chain.forTrace(innerTrace),
        super(message);
}

/// A class for exceptions that shouldn't be printed at the top level.
///
/// This is usually used when an exception has already been printed using
/// [log.exception].
class SilentException extends WrappedException {
  SilentException(innerError, [StackTrace innerTrace])
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
  /// If this failure was caused by an SDK being unavailable, this is that SDK.
  final Sdk missingSdk;

  PackageNotFoundException(String message,
      {innerError, StackTrace innerTrace, this.missingSdk})
      : super(message, innerError, innerTrace);

  @override
  String toString() => "Package doesn't exist ($message).";
}

/// Returns whether [error] is a user-facing error object.
///
/// This includes both [ApplicationException] and any dart:io errors.
bool isUserFacingException(error) {
  // TODO(nweiz): unify this list with _userFacingExceptions when issue 5897 is
  // fixed.
  return error is ApplicationException ||
      error is AnalyzerErrorGroup ||
      error is IsolateSpawnException ||
      error is IOException ||
      error is http.ClientException ||
      error is YamlException ||
      error is UsageException;
}
