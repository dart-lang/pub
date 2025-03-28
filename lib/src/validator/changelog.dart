// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../io.dart';
import '../validator.dart';

final _changelogRegexp = RegExp(r'^CHANGELOG($|\.)', caseSensitive: false);

/// A validator that validates a package's changelog file.
class ChangelogValidator extends Validator {
  @override
  Future<void> validate() async {
    final changelog = filesBeneath(
      '.',
      recursive: false,
    ).firstWhereOrNull((entry) => p.basename(entry).contains(_changelogRegexp));

    if (changelog == null) {
      warnings.add(
        'Please add a `CHANGELOG.md` to your package. '
        'See https://dart.dev/tools/pub/publishing#important-files.',
      );
      return;
    }

    if (p.basename(changelog) != 'CHANGELOG.md') {
      warnings.add(
        'Please consider renaming $changelog to `CHANGELOG.md`. '
        'See https://dart.dev/tools/pub/publishing#important-files.',
      );
    }

    final bytes = readBinaryFile(changelog);
    String contents;

    try {
      // utf8.decode doesn't allow invalid UTF-8.
      contents = utf8.decode(bytes);
    } on FormatException catch (_) {
      warnings.add(
        '$changelog contains invalid UTF-8.\n'
        'This will cause it to be displayed incorrectly on '
        'the Pub site (https://pub.dev).',
      );
      // Failed to decode contents, so there's nothing else to check.
      return;
    }

    final version = package.pubspec.version.toString();

    if (!contents.contains(version)) {
      warnings.add(
        "$changelog doesn't mention current version ($version).\n"
        'Consider updating it with notes on this version prior to '
        'publication.',
      );
    }
  }
}
