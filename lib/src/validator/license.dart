// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;

import '../entrypoint.dart';
import '../validator.dart';

/// A validator that checks that a LICENSE-like file exists.
class LicenseValidator extends Validator {
  LicenseValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate(List<String> files) {
    return Future.sync(() {
      final licenseLike =
          RegExp(r'^(([a-zA-Z0-9]+[-_])?(LICENSE|COPYING)|UNLICENSE)(\..*)?$');
      final canonicalRootDir = p.canonicalize(entrypoint.root.dir);
      final candidates = files.where((entry) =>
          licenseLike.hasMatch(p.basename(entry)) &&
          p.canonicalize(p.dirname(entry)) == canonicalRootDir);
      if (candidates.isNotEmpty) {
        if (!candidates
            .any((candidate) => p.basename(candidate) == 'LICENSE')) {
          final firstCandidate = candidates.first;
          warnings.add('Please consider renaming $firstCandidate to `LICENSE`. '
              'See https://dart.dev/tools/pub/publishing#important-files.');
        }
        return;
      }

      errors.add('You must have a LICENSE file in the root directory.\n'
          'An open-source license helps ensure people can legally use your '
          'code.');
    });
  }
}
