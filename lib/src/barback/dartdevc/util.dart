// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

/// Returns the top level directory in [path].
///
/// Throws an [ArgumentError] if [path] is just a filename with no directory.
String topLevelDir(String path) {
  var parts = p.url.split(path);
  if (parts.isEmpty) {
    throw new ArgumentError(
        'Cannot compute top level dir for path `$path`. The file does not live '
        'under a directory.');
  }
  return parts.first;
}

/// Convert [url] found in [source] to an [AssetId].
///
/// Throws an [ArgumentError] if an [AssetId] cannot be created.
///
/// Returns [null] for `dart:` uris.
AssetId urlToAssetId(AssetId source, String url) {
  var uri = Uri.parse(url);
  if (uri.isAbsolute) {
    if (uri.scheme == 'package') {
      var parts = uri.pathSegments;
      return new AssetId(
          parts.first, p.url.joinAll(['lib']..addAll(parts.skip(1))));
    } else if (uri.scheme == 'dart') {
      return null;
    } else {
      throw new ArgumentError(
          'Unable to resolve import. Only package: paths and relative '
          'paths are supported, got `$url`.');
    }
  } else {
    // Relative path.
    var targetPath =
        p.url.normalize(p.url.join(p.url.dirname(source.path), uri.path));
    return new AssetId(source.package, targetPath);
  }
}
