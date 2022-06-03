// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../io.dart';
import '../validator.dart';

final _readmeRegexp = RegExp(r'^README($|\.)', caseSensitive: false);

/// Validates that a package's README exists and is valid utf-8.
class ReadmeValidator extends Validator {
  @override
  Future<void> validate() async {
    // Find the path to the README file at the root of the entrypoint.
    //
    // If multiple READMEs are found, this uses the same conventions as
    // pub.dev for choosing the primary one: the README with the fewest
    // extensions that is lexically ordered first is chosen.
    final readmes = filesBeneath('.', recursive: false)
        .where((file) => p.basename(file).contains(_readmeRegexp));

    if (readmes.isEmpty) {
      warnings.add('Please add a README.md file that describes your package.');
      return;
    }

    final readme = readmes.reduce((readme1, readme2) {
      final extensions1 = '.'.allMatches(p.basename(readme1)).length;
      final extensions2 = '.'.allMatches(p.basename(readme2)).length;
      var comparison = extensions1.compareTo(extensions2);
      if (comparison == 0) comparison = readme1.compareTo(readme2);
      return (comparison <= 0) ? readme1 : readme2;
    });

    if (p.basename(readme) != 'README.md') {
      warnings.add('Please consider renaming $readme to `README.md`. '
          'See https://dart.dev/tools/pub/publishing#important-files.');
    }

    var bytes = readBinaryFile(readme);
    try {
      // utf8.decode doesn't allow invalid UTF-8.
      utf8.decode(bytes);
    } on FormatException catch (_) {
      warnings.add('$readme contains invalid UTF-8.\n'
          'This will cause it to be displayed incorrectly on '
          'the Pub site (https://pub.dev).');
    }
  }
}
