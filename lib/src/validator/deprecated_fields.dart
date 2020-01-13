// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../entrypoint.dart';
import '../validator.dart';

/// A validator that validates that a pubspec is not including deprecated fields
/// which are no longer read.
class DeprecatedFieldsValidator extends Validator {
  DeprecatedFieldsValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate() async {
    if (entrypoint.root.pubspec.fields.containsKey('transformers')) {
      warnings.add('Your pubpsec.yaml includes a "transformers" section which'
          ' is no longer used and may be removed.');
    }
    if (entrypoint.root.pubspec.fields.containsKey('web')) {
      warnings.add('Your pubspec.yaml includes a "web" section which'
          ' is no longer used and may be removed.');
    }
    if (entrypoint.root.pubspec.fields.containsKey('author')) {
      warnings.add('Your pubspec.yaml includes an "author" section which'
          ' is no longer used and may be removed.');
    }
    if (entrypoint.root.pubspec.fields.containsKey('authors')) {
      warnings.add('Your pubspec.yaml includes an "authors" section which'
          ' is no longer used and may be removed.');
    }
  }
}
