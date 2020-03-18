// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../entrypoint.dart';
import '../validator.dart';

/// A validator that checks that the pubspec has valid "author" and "homepage"
/// fields.
class PubspecFieldValidator extends Validator {
  PubspecFieldValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate() {
    _validateFieldIsString('description');
    _validateFieldUrl('homepage');
    _validateFieldUrl('repository');
    if (!_hasField('homepage') && !_hasField('repository')) {
      warnings.add(
        'It\'s strongly recommended to include a "homepage" or '
        '"repository" field in your pubspec.yaml',
      );
    }

    _validateFieldUrl('documentation');

    // Any complex parsing errors in version will be exposed through
    // [Pubspec.allErrors].
    _validateFieldIsString('version');

    // Pubspec errors are detected lazily, so we make sure there aren't any
    // here.
    for (var error in entrypoint.root.pubspec.allErrors) {
      errors.add('In your pubspec.yaml, ${error.message}');
    }

    return Future.value();
  }

  bool _hasField(String field) => entrypoint.root.pubspec.fields[field] != null;

  /// Adds an error if [field] doesn't exist or isn't a string.
  void _validateFieldIsString(String field) {
    var value = entrypoint.root.pubspec.fields[field];
    if (value == null) {
      errors.add('Your pubspec.yaml is missing a "$field" field.');
    } else if (value is! String) {
      errors.add('Your pubspec.yaml\'s "$field" field must be a string, but '
          'it was "$value".');
    }
  }

  /// Adds an error if the URL for [field] is invalid.
  void _validateFieldUrl(String field) {
    var url = entrypoint.root.pubspec.fields[field];
    if (url == null) return;

    if (url is! String) {
      errors.add('Your pubspec.yaml\'s "$field" field must be a string, but '
          'it was "$url".');
      return;
    }

    var goodScheme = RegExp(r'^https?:');
    if (!goodScheme.hasMatch(url)) {
      errors.add('Your pubspec.yaml\'s "$field" field must be an "http:" or '
          '"https:" URL, but it was "$url".');
    }
  }
}
