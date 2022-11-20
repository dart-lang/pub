// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/git_url.dart';
import 'package:test/test.dart';

void main() {
  test('correct https url', () {
    const gitUrl = 'https://github.com/dart-lang/pub.git';
    final uri = Uri.parse(gitUrl);
    expect(parseGitUrl(gitUrl), equals(uri.toString()));
  });

  test('current directory path', () {
    const gitUrl = 'foo.git';
    expect(parseGitUrl(gitUrl), equals(gitUrl));
  });

  test('other directory path', () {
    const gitUrl = '../foo.git';
    expect(parseGitUrl(gitUrl), equals(gitUrl));
  });

  test('correct git url', () {
    const gitUrl = 'git@github.com:dart-lang/pub.git';
    expect(parseGitUrl(gitUrl), equals(gitUrl));
  });

  group('git url exception', () {
    test('invalid git format', () {
      const gitUrl = 'git@github.com:dart-lang/pub';
      expect(() => parseGitUrl(gitUrl), throwsA(isA<GitUrlException>()));
    });

    test('need domain', () {
      const gitUrl = 'git@dart-lang/pub.git';
      expect(() => parseGitUrl(gitUrl), throwsA(isA<GitUrlException>()));
    });

    test('invalid domain', () {
      const gitUrl = 'git@:dart-lang/pub.git';
      expect(() => parseGitUrl(gitUrl), throwsA(isA<GitUrlException>()));
    });
  });
}
