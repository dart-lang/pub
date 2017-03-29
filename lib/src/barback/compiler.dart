// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const _dart2JsName = 'dart2js';
const _dartDevcName = 'dartdevc';
const _noneName = 'none';

/// The compiler currently being used (or none).
///
/// This is controlled by the `--compiler=$name` flag.
class Compiler {
  static final dart2Js = new Compiler._(_dart2JsName);
  static final dartDevc = new Compiler._(_dartDevcName);
  static final none = new Compiler._(_noneName);

  static final compilers = [dart2Js, dartDevc, none];
  static Iterable<String> get compilerNames =>
      compilers.map((compiler) => compiler.name);

  final String name;

  Compiler._(this.name);

  static Compiler byName(String name) =>
      compilers.firstWhere((compiler) => compiler.name == name, orElse: () {
        throw 'Unrecognized compiler `$name`, supported compilers are '
            '`${compilerNames.join(", ")}`.';
      });

  String toString() => name;
}
