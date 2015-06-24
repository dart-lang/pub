// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Keeps track of locations of packages, and can create a `.packages` file.
// TODO(lrn): Also move packages/ directory management to this library.
library pub.package_locations;

import 'dart:async';

import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;

import 'package_graph.dart';
import 'io.dart';
import 'log.dart' as log;
import 'utils.dart' show ordered;

/// Creates a `.packages` file with the locations of the packages in [graph].
///
/// The file is written in the root directory of the entrypoint of [graph].
///
/// If the file already exists, it is deleted before the new content is written.
void writePackagesMap(PackageGraph graph) {
  var packagesFilePath = graph.entrypoint.root.path(".packages");
  var content = _createPackagesMap(graph);
  writeTextFile(packagesFilePath, content);
}

/// Template for header text put into `.packages` file.
///
/// Contains the literal string `$now` which should be replaced by a timestamp.
const _headerText = r"""
Generate by pub on $now.
This file contains a map from Dart package names to Dart package locations.
Dart tools, including the Dart VM and Dart analyzer, rely on the content.
AUTO GENERATED - DO NOT EDIT
""";

/// Returns the contents of the `.packages` file created from a package graph.
///
/// The paths in the generated `.packages` file are always absolute URIs.
String _createPackagesMap(PackageGraph packageGraph) {
  var header = _headerText.replaceFirst(r"$now", new DateTime.now().toString());

  var packages = packageGraph.packages;
  var uriMap = {};
  for (var packageName in ordered(packages.keys)) {
    var location = packages[packageName].path("lib");
    uriMap[packageName] = p.toUri(location);
  }

  var text = new StringBuffer();
  packages_file.write(text, uriMap, comment: header);
  return text.toString();
}
