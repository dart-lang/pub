// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../entrypoint.dart';
import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:pub/src/solver/version_solver.dart';
import 'package:pub/src/validator.dart';

/// Returns a map of files -> package names imported or exported within [files].
Map<String, Iterable<String>> _findUsedPackages(Iterable<String> files) {
  var packageNames = <String, Iterable<String>>{};
  for (var file in files) {
    var usedPackages = <String>[];
    var compilationUnit = parseDirectives(new File(file).readAsStringSync());
    for (final directive in compilationUnit.directives) {
      if (directive is UriBasedDirective) {
        usedPackages
            .add(Uri.parse(directive.uri.stringValue).pathSegments.first);
      }
    }
    packageNames[file] = usedPackages.toSet();
  }
  return packageNames;
}

class StrictDependenciesValidator extends Validator {
  StrictDependenciesValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate() {
    return new Future.sync(() async {
      var declared = new Set<String>()
        ..addAll(entrypoint.root.dependencies.map((d) => d.name))
        ..addAll(entrypoint.root.devDependencies.map((d) => d.name));
      var allUsed = _findUsedPackages(entrypoint.root.listFiles());
      allUsed.forEach((file, packageNames) {
        for (var package in packageNames) {
          if (!declared.contains(package)) {
            warnings.add(
                'Referenced "$package" in $file, but no dependency declared');
          }
        }
      });
    });
  }
}
