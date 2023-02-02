// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/language_version.dart';

import 'package:pub/src/source/git.dart';

import 'package:test/test.dart';

void main() {
  // These tests are not integration tests because it seems to be hard to
  // actually test this kind of urls locally. We would have to set up serving
  // git over ssh.
  //
  // We could set up a local cache, and only test the '--offline' part of this.
  // But for now we live with this.
  test(
      'Git description uris can be of the form git@github.com:dart-lang/pub.git',
      () {
    final description = GitDescription(
      url: 'git@github.com:dart-lang/pub.git',
      ref: 'main',
      path: 'abc/',
      containingDir: null,
    );
    expect(
      description.format(),
      'git@github.com:dart-lang/pub.git at main in abc/',
    );
    expect(
      description.serializeForPubspec(
        containingDir: null,
        languageVersion: LanguageVersion(2, 16),
      ),
      {
        'url': 'git@github.com:dart-lang/pub.git',
        'ref': 'main',
        'path': 'abc/',
      },
    );
    final resolvedDescription = GitResolvedDescription(
      description,
      '7d48f902b0326fc2ce0615c20f1aab6c811fe55b',
    );

    expect(
      resolvedDescription.format(),
      'git@github.com:dart-lang/pub.git at 7d48f9 in abc/',
    );
    expect(
      resolvedDescription.serializeForLockfile(containingDir: null),
      {
        'url': 'git@github.com:dart-lang/pub.git',
        'ref': 'main',
        'path': 'abc/',
        'resolved-ref': '7d48f902b0326fc2ce0615c20f1aab6c811fe55b',
      },
    );
  });
}
