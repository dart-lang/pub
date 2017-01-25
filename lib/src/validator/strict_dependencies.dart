// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:path/path.dart' as path;
import 'package:pub/src/dart.dart';
import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/validator.dart';
import 'package:source_span/source_span.dart';

class StrictDependenciesValidator extends Validator {
  static bool _isDartFile(String file) => path.extension(file) == '.dart';

  StrictDependenciesValidator(Entrypoint entrypoint) : super(entrypoint);

  /// Returns all pub packages imported or exported within [files].
  List<_DependencyUse> _findPackages(Iterable<String> files) {
    var allUses = <_DependencyUse>[];
    for (var file in files) {
      var dependencies = new List<_DependencyUse>();
      try {
        var contents = readTextFile(file);
        var directives = parseImportsAndExports(contents, name: file);
        for (var directive in directives) {
          var usage = new _DependencyUse(directive, file, contents);
          if (usage.isPubPackage) {
            dependencies.add(usage);
          }
        }
        allUses.addAll(dependencies);
      } on AnalyzerErrorGroup catch (e) {
        warnings.add('Failed parsing "$file": $e');
      }
    }
    return allUses;
  }

  Future validate() async {
    var declared = new Set<String>()
      ..addAll(entrypoint.root.dependencies.map((d) => d.name))
      ..addAll(entrypoint.root.devDependencies.map((d) => d.name))
      ..add(entrypoint.root.name);
    var allUsed = _findPackages(entrypoint.root.listFiles().where(_isDartFile));
    for (var usage in allUsed) {
      if (!declared.contains(usage.package)) {
        warnings.add(usage.toErrorMessage());
      }
    }
  }
}

class _DependencyUse {
  final String _contents;
  final UriBasedDirective _directive;
  final String _file;
  final Uri _parsedUri;

  _DependencyUse(UriBasedDirective directive, this._file, this._contents)
      : _parsedUri = Uri.parse(directive.uri.stringValue),
        _directive = directive;

  bool get isPubPackage => _parsedUri.scheme == 'package';

  String get package => _parsedUri.pathSegments.first;

  String toErrorMessage() {
    return new SourceFile(_contents, url: _file)
        .span(_directive.offset, _directive.length)
        .message(
            '$_file imports $package, but this package doesn\'t depend '
            'on $package');
  }
}
