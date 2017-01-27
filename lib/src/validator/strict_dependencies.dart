// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:pub/src/dart.dart';
import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/log.dart';
import 'package:pub/src/validator.dart';
import 'package:source_span/source_span.dart';

/// Validates that Dart source files only import declared dependencies.
class StrictDependenciesValidator extends Validator {
  static Iterable<String> _combine(Iterable<String> a, Iterable<String> b) {
    return a.toList()..addAll(b);
  }

  StrictDependenciesValidator(Entrypoint entrypoint) : super(entrypoint);

  Set<String> _dependencies;

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
        exception(e, s);
        continue;
      }
      for (var directive in directives) {
        Uri uri;
        try {
          uri = Uri.parse(directive.uri.stringValue);
        } on FormatException catch (_){}
        var usage = new _Usage(file, contents, directive, uri);
        if (usage.isPackageUrl) {
          yield usage;
        }
      }
    }
  }

  /// Returns whether [package] is listed under `dependencies: `.
  ///
  /// The current package is implicitly a dependency.
  bool _isDependency(String package) {
    if (_dependencies == null) {
      _dependencies = entrypoint.root.dependencies
          .map((d) => d.name)
          .toSet();
    }
    return entrypoint.root.name == package || _dependencies.contains(package);
  }

  Set<String> _devDependencies;

  /// Returns whether [package] is listed under `dev_dependencies: `.
  bool _isDevDependency(String package) {
    if (_devDependencies == null) {
      _devDependencies = entrypoint.root.devDependencies
          .map((d) => d.name)
          .toSet();
    }
    return _devDependencies.contains(package);
  }

  Future validate() async {
    _validateLibBin();
    _validateTestTool();
  }

  void _validateLibBin() {
    var libFiles = entrypoint.root.listFiles(beneath: 'lib');
    var binFiles = entrypoint.root.listFiles(beneath: 'bin');
    for (var usage in _findPackages(_combine(libFiles, binFiles))) {
      if (!usage.isUriValid) {
        warnings.add(usage.uriInvalidMessage());
      } else if (!_isDependency(usage.package)) {
        if (_isDevDependency(usage.package)) {
          warnings.add(usage.dependencyMisplaceMessage());
        } else {
          warnings.add(usage.dependencyMissingMessage());
        }
      }
    }
  }

  void _validateTestTool() {
    var testFiles = entrypoint.root.listFiles(beneath: 'test');
    var toolFiles = entrypoint.root.listFiles(beneath: 'tool');
    for (var usage in _findPackages(_combine(testFiles, toolFiles))) {
      if (!usage.isUriValid) {
        warnings.add(usage.uriInvalidMessage());
      } else if (!_isDependency(usage.package) &&
                 !_isDevDependency(usage.package)) {
        warnings.add(usage.dependencyMissingMessage());
      }
    }
  }
}

/// Represents a parsed import or export directive in a dart source file.
class _Usage {
  final String _contents;
  final String _file;
  final Uri _uri;
  final UriBasedDirective _directive;

  _Usage(this._file, this._contents, this._directive, this._uri);

  /// Returns the package name if [isPackageUrl], otherwise `null`.
  String get package => isPackageUrl ? _uri.pathSegments.first : null;

  /// Returns whether the URI was parsable and correct in the directive.
  bool get isUriValid => _uri != null && _uri.pathSegments.length >= 2;

  /// Returns whether the directive references a pub package.
  bool get isPackageUrl => _uri.scheme == 'package';

  // Assumption is that normally all directives are valid and we won't see
  // an error message - so a SourceFile is created lazily (on demand) to avoid
  // parsing line endings in the case of only valid directives.
  String _toMessage(String message) => new SourceFile(_contents, url: _file)
      .span(_directive.offset, _directive.offset + _directive.length)
      .message(message);

  /// Returns an error message saying that the URI is invalid.
  String uriInvalidMessage() {
    assert(!isUriValid);
    var uri = _directive.uri.stringValue;
    return _toMessage('$_file references an invalid URI: $uri');
  }

  /// Returns an error message saying the package is not listed in dependencies.
  String dependencyMissingMessage() {
    return _toMessage(
      '$_file imports $package, but this package doesn\'t depend on $package.'
    );
  }

  /// Returns an error message saying the package should be in `dependencies`.
  String dependencyMisplaceMessage() {
    return _toMessage(
      '$_file imports $package, but is only listed in `devDependencies`. Files '
      'in the `lib` or `bin` folder must declare in `dependencies` - '
      'devDependencies is only valid for files in `tool` or `test`.'
    );
  }
}
