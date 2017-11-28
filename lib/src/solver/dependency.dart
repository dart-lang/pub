// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../package_name.dart';

/// A reference from a depending package to a package that it depends on.
class Dependency {
  /// The package that has this dependency.
  final PackageId depender;

  /// The package being depended on.
  final PackageRange dep;

  Dependency(this.depender, this.dep);

  String toString() => '$depender -> $dep';
}
