// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const _dart2JSName = 'dart2js';
const _dartDevcName = 'dartdevc';
const _noneName = 'none';

/// The compiler currently being used (or none).
///
/// This is controlled by the `--compiler=$name` flag.
class Compiler {
  static const dart2JS = const Compiler._(_dart2JSName);
  static const dartDevc = const Compiler._(_dartDevcName);
  static const none = const Compiler._(_noneName);

  static final all = [dart2JS, dartDevc, none];

  static Iterable<String> get names => all.map((compiler) => compiler.name);

  final String name;

  const Compiler._(this.name);

  static Compiler byName(String name) =>
      all.firstWhere((compiler) => compiler.name == name, orElse: () {
        throw new ArgumentError(
            'Unrecognized compiler `$name`, supported compilers are '
            '`${names.join(", ")}`.');
      });

  String toString() => name;
}
