// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';

import 'package:pub/src/compiler.dart';

// For convenience, otherwise we need this import in pretty much all tests.
export 'package:pub/src/compiler.dart';

/// Runs a test once for each [Compiler] in [compilers], defaulting to
/// [Compiler.dart2JS] and [Compiler.dartDevc].
void testWithCompiler(String name, FutureOr testFn(Compiler compiler),
    {List<Compiler> compilers}) {
  compilers ??= [Compiler.dart2JS, Compiler.dartDevc];
  for (var compiler in compilers) {
    test('--web-compiler=${compiler.name} $name', () => testFn(compiler));
  }
}
