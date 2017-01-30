// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:pub/src/dart.dart';
import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/log.dart' as log;
import 'package:pub/src/utils.dart';
import 'package:pub/src/validator.dart';
import 'package:source_span/source_span.dart';
import 'package:stack_trace/stack_trace.dart';

/// Validates that Dart source files only import declared dependencies.
class StrictDependenciesValidator extends Validator {
  StrictDependenciesValidator(Entrypoint entrypoint) : super(entrypoint);

  /// Lazily returns all dependency uses in [files].
  ///
  /// Files that do not parse are skipped.
  ///
  /// Directives that do not import package: URIs are skipped.
  Iterable<_Usage> _findPackages(Iterable<String> files) sync* {
    for (var file in files) {
      List<UriBasedDirective> directives;
      var contents = readTextFile(file);
      try {
        directives = parseImportsAndExports(contents, name: file);
      } on AnalyzerErrorGroup catch (e, s) {
        // Ignore files that do not parse.
        log.fine(getErrorMessage(e));
        log.fine(new Chain.forTrace(s).terse);
        continue;
      }
      for (var directive in directives) {
        Uri uri;
        try {
          uri = Uri.parse(directive.uri.stringValue);
        } on FormatException catch (_){}
        // If the URL could not be parsed or it is a *package* AND
        // there are no segments OR
        // any segment are empty
        if (uri == null ||
            (uri.scheme == 'package' &&
            (uri.pathSegments.length < 2 ||
            uri.pathSegments.any((s) => s.isEmpty)))) {
          warnings.add(_Usage.errorMessage(
            'Invalid URL',
            file,
            contents,
            directive
          ));
        } else if (uri.scheme == 'package') {
          var usage = new _Usage(file, contents, directive, uri);
          yield usage;
        }
      }
    }
  }

  Future validate() async {
    var dependencies = entrypoint.root.dependencies
        .map((d) => d.name)
        .toSet()
        ..add(entrypoint.root.name);
    var devDependencies = entrypoint.root.devDependencies
        .map((d) => d.name)
        .toSet();
    _validateLibBin(dependencies, devDependencies);
    _validateTestTool(dependencies, devDependencies);
  }

  static bool _isDart(String file) => p.extension(file) == '.dart';

  void _validateLibBin(Set<String> deps, Set<String> devDeps) {
    var libFiles = entrypoint.root.listFiles(beneath: 'lib').where(_isDart);
    var binFiles = entrypoint.root.listFiles(beneath: 'bin').where(_isDart);
    for (var usage in _findPackages(combineIterables(libFiles, binFiles))) {
      if (!deps.contains(usage.package)) {
        if (devDeps.contains(usage.package)) {
          warnings.add(usage.dependencyMisplaceMessage());
        } else {
          warnings.add(usage.dependencyMissingMessage());
        }
      }
    }
  }

  void _validateTestTool(Set<String> deps, Set<String> devDeps) {
    var testFiles = entrypoint.root.listFiles(beneath: 'test').where(_isDart);
    var toolFiles = entrypoint.root.listFiles(beneath: 'tool').where(_isDart);
    for (var usage in _findPackages(combineIterables(testFiles, toolFiles))) {
      if (!deps.contains(usage.package) &&
          !devDeps.contains(usage.package)) {
        warnings.add(usage.dependencyMissingMessage());
      }
    }
  }
}

/// Represents a parsed import or export directive in a dart source file.
class _Usage {
  /// Returns a formatted error message highlighting [directive] in [file].
  static String errorMessage(
      String message,
      String file,
      String contents,
      UriBasedDirective directive) {
    return new SourceFile(contents, url: file)
        .span(directive.offset, directive.offset + directive.length)
        .message(message);
  }

  final String _contents;
  final String _file;
  final Uri _uri;
  final UriBasedDirective _directive;

  _Usage(this._file, this._contents, this._directive, this._uri);

  /// Returns the package name.
  String get package => _uri.pathSegments.first;

  // Assumption is that normally all directives are valid and we won't see
  // an error message - so a SourceFile is created lazily (on demand) to avoid
  // parsing line endings in the case of only valid directives.
  String _toMessage(String message) =>
      errorMessage(message, _file, _contents, _directive);

  /// Returns an error message saying the package is not listed in dependencies.
  String dependencyMissingMessage() {
    return _toMessage('This packagee doesn\'t depend on $package.');
  }

  /// Returns an error message saying the package should be in `dependencies`.
  String dependencyMisplaceMessage() {
    var shortFile = p.split(p.relative(_file)).first;
    return _toMessage(
      '$package is a dev dependency. Packages used in $shortFile/ must be '
      'declared as normal dependencies.'
    );
  }
}
