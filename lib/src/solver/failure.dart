// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../exceptions.dart';
import 'incompatibility.dart';

/// Base class for all failures that can occur while trying to resolve versions.
class SolveFailure implements ApplicationException {
  /// The root incompatibility.
  ///
  /// This will always indicate that the root package is unselectable. That is,
  /// it will have one term, which will be the root package.
  final Incompatibility incompatibility;

  String get message => toString();

  SolveFailure(this.incompatibility) {
    assert(incompatibility.terms.single.package.isRoot);
  }

  // TODO(nweiz): Produce a useful error message.
  String toString() => "Tough luck, Chuck!";
}
