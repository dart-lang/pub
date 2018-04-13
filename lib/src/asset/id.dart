// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Like the AssetId class from barback but without the barback dependency.
class AssetId {
  final String package;
  final String path;
  AssetId(this.package, this.path);
}
