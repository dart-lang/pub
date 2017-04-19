// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;

import '../../io.dart';

/// Returns a canonical uri for [id].
///
/// If [id] is under a `lib` directory then this returns a `package:` uri,
/// otherwise it just returns [id.path].
String canonicalUriFor(AssetId id) {
  if (topLevelDir(id.path) == 'lib') {
    return 'package:${p.join(id.package, p.joinAll(p.split(id.path).skip(1)))}';
  } else {
    return id.path;
  }
}
