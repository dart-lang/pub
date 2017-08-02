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
  /// Files that do not parse and directives that don't import or export
  /// `package:` URLs are ignored.
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
        Uri url;
        try {
          url = Uri.parse(directive.uri.stringValue);
        } on FormatException catch (_) {
          // Ignore a format exception. [url] will be null, and we'll emit an
          // "Invalid URL" warning below.
        }

        // If the URL could not be parsed or it is a `package:` URL AND there
        // are no segments OR any segment are empty, it's invalid.
        if (url == null ||
            (url.scheme == 'package' &&
                (url.pathSegments.length < 2 ||
                    url.pathSegments.any((s) => s.isEmpty)))) {
          warnings.add(
              _Usage.errorMessage('Invalid URL.', file, contents, directive));
        } else if (url.scheme == 'package') {
          yield new _Usage(file, contents, directive, url);
        }
      }
    }
  }

  Future validate() async {
    var dependencies = entrypoint.root.dependencies.map((d) => d.name).toSet()
      ..add(entrypoint.root.name);
    var devDependencies =
        entrypoint.root.devDependencies.map((d) => d.name).toSet();
    _validateLibBin(dependencies, devDependencies);
    _validateBenchmarkExampleTestTool(dependencies, devDependencies);
  }

  /// Validates that no Dart files in `lib/` or `bin/` have dependencies that
  /// aren't in [deps].
  ///
  /// The [devDeps] are used to generate special warnings for files that import
  /// dev dependencies.
  void _validateLibBin(Set<String> deps, Set<String> devDeps) {
    for (var usage in _usagesBeneath(['lib', 'bin'])) {
      if (!deps.contains(usage.package)) {
        if (devDeps.contains(usage.package)) {
          warnings.add(usage.dependencyMisplaceMessage());
        } else {
          warnings.add(usage.dependencyMissingMessage());
        }
      }
    }
  }

  /// Validates that no Dart files in `benchmark/`, `example/, `test/` or
  /// `tool/` have dependencies that aren't in [deps] or [devDeps].
  void _validateBenchmarkExampleTestTool(
      Set<String> deps, Set<String> devDeps) {
    for (var usage
        in _usagesBeneath(['benchmark', 'example', 'test', 'tool'])) {
      if (!deps.contains(usage.package) && !devDeps.contains(usage.package)) {
        warnings.add(usage.dependencyMissingMessage());
      }
    }
  }

  Iterable<_Usage> _usagesBeneath(List<String> paths) => _findPackages(paths
      .map((path) => entrypoint.root.listFiles(beneath: path))
      .expand((files) => files)
      .where((String file) => p.extension(file) == '.dart'));
}

/// A parsed import or export directive in a D source file.
class _Usage {
  /// Returns a formatted error message highlighting [directive] in [file].
  static String errorMessage(String message, String file, String contents,
      UriBasedDirective directive) {
    return new SourceFile.fromString(contents, url: file)
        .span(directive.offset, directive.offset + directive.length)
        .message(message);
  }

  /// The path to the file from which [_directive] was parsed.
  final String _file;

  /// The contents of [_file].
  final String _contents;

  /// The URI parsed from [_directive].
  final Uri _url;

  /// The directive that uses [_url].
  final UriBasedDirective _directive;

  _Usage(this._file, this._contents, this._directive, this._url);

  /// The name of the package referred to by this usage..
  String get package => _url.pathSegments.first;

  /// Returns a message associated with [_directive].
  ///
  /// We assume that normally all directives are valid and we won't see an error
  /// message, so we create the SourceFile lazily to avoid parsing line endings
  /// in the case of only valid directives.
  String _toMessage(String message) =>
      errorMessage(message, _file, _contents, _directive);

  /// Returns an error message saying the package is not listed in dependencies.
  String dependencyMissingMessage() =>
      _toMessage("This package doesn't depend on $package.");

  /// Returns an error message saying the package should be in `dependencies`.
  String dependencyMisplaceMessage() {
    var shortFile = p.split(p.relative(_file)).first;
    return _toMessage(
        '$package is a dev dependency. Packages used in $shortFile/ must be '
        'declared as normal dependencies.');
  }
}
