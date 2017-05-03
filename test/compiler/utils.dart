// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/barback/compiler.dart';

import '../test_pub.dart';

// For convenience, otherwise we need this import in pretty much all tests.
export 'package:pub/src/barback/compiler.dart';

/// Runs an integration test once for each [Compiler] in [compilers], defaulting
/// to [Compiler.dart2JS] and [Compiler.dartDevc].
void integrationWithCompiler(String name, void testFn(Compiler compiler),
    {List<Compiler> compilers}) {
  compilers ??= [Compiler.dart2JS, Compiler.dartDevc];
  for (var compiler in compilers) {
    integration('--compiler=${compiler.name} $name', () => testFn(compiler));
  }
}
