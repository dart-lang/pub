// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:stack_trace/stack_trace.dart';

import '../dart.dart';
import '../io.dart';
import '../log.dart' as log;
import '../utils.dart';
import '../validator.dart';

/// Validates that Dart source files only import declared dependencies.
class StrictDependenciesValidator extends Validator {
  /// Lazily returns all dependency uses in [files].
  ///
  /// Files that do not parse and directives that don't import or export
  /// `package:` URLs are ignored.
  Iterable<_Usage> _findPackages(Iterable<String> files) sync* {
    final packagePath = p.normalize(p.absolute(package.dir));
    final analysisContextManager = AnalysisContextManager(packagePath);

    for (var file in files) {
      List<UriBasedDirective> directives;
      final contents = readTextFile(file);
      try {
        directives = analysisContextManager.parseImportsAndExports(file);
      } on AnalyzerErrorGroup catch (e, s) {
        // Ignore files that do not parse.
        log.fine(getErrorMessage(e));
        log.fine(Chain.forTrace(s).terse.toString());
        continue;
      }

      for (var directive in directives) {
        Uri? url;
        final uriString = directive.uri.stringValue;
        if (uriString != null) {
          url = Uri.tryParse(uriString);
        }

        // If the URL could not be parsed or it is a `package:` URL AND there
        // are no segments OR any segment are empty, it's invalid.
        if (url == null ||
            (url.scheme == 'package' &&
                (url.pathSegments.length < 2 ||
                    url.pathSegments.any((s) => s.isEmpty)))) {
          errors.add(
            _Usage.errorMessage('Invalid URL.', file, contents, directive),
          );
        } else if (url.scheme == 'package') {
          yield _Usage(file, contents, directive, url);
        }
      }
    }
  }

  @override
  Future validate() async {
    final dependencies = package.dependencies.keys.toSet()..add(package.name);
    final devDependencies = MapKeySet(package.devDependencies);
    _validateLibBinHook(dependencies, devDependencies);
    _validateBenchmarkTestTool(dependencies, devDependencies);
  }

  /// Validates that no Dart files in `lib/`, `bin/`, `hook/build.dart`, or
  /// `hook/link.dart` have dependencies that aren't in [deps].
  ///
  /// The [devDeps] are used to generate special warnings for files that import
  /// dev dependencies.
  void _validateLibBinHook(Set<String> deps, Set<String> devDeps) {
    for (var usage in _usagesBeneath([
      'bin',
      'hook/build.dart',
      'hook/link.dart',
      'lib',
    ])) {
      if (!deps.contains(usage.package)) {
        if (devDeps.contains(usage.package)) {
          errors.add(usage.dependencyMisplaceMessage());
        } else {
          errors.add(usage.dependencyMissingMessage());
        }
      }
    }
  }

  /// Validates that no Dart files in `benchmark/`, `test/` or
  /// `tool/` have dependencies that aren't in [deps] or [devDeps].
  void _validateBenchmarkTestTool(Set<String> deps, Set<String> devDeps) {
    final directories = ['benchmark', 'test', 'tool'];
    for (var usage in _usagesBeneath(directories)) {
      if (!deps.contains(usage.package) && !devDeps.contains(usage.package)) {
        warnings.add(usage.dependenciesMissingMessage());
      }
    }
  }

  Iterable<_Usage> _usagesBeneath(List<String> paths) {
    return _findPackages(
      paths.expand((path) {
        return filesBeneath(
          path,
          recursive: true,
        ).where((file) => p.extension(file) == '.dart');
      }),
    );
  }
}

/// A parsed import or export directive in a D source file.
class _Usage {
  /// Returns a formatted error message highlighting [directive] in [file].
  static String errorMessage(
    String message,
    String file,
    String contents,
    UriBasedDirective directive,
  ) {
    return SourceFile.fromString(contents, url: file)
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

  /// Returns an error message saying the package is not listed in
  /// `dependencies`.
  String dependencyMissingMessage() => _toMessage(
    'This package does not have $package in the `dependencies` '
    'section of `pubspec.yaml`.',
  );

  /// Returns an error message saying the package is not listed in
  ///  `dependencies` or `dev_dependencies`.
  String dependenciesMissingMessage() => _toMessage(
    'This package does not have $package in the `dependencies` '
    'or `dev_dependencies` section of `pubspec.yaml`.',
  );

  /// Returns an error message saying the package should be in `dependencies`.
  String dependencyMisplaceMessage() {
    final shortFile = p.split(p.relative(_file)).first;
    return _toMessage(
      '$package is in the `dev_dependencies` section of `pubspec.yaml`. '
      'Packages used in $shortFile/ must be declared in the `dependencies` '
      'section.',
    );
  }
}
