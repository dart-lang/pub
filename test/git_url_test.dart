// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/git_url.dart';
import 'package:test/test.dart';

void main() {
  group('parse()', () {
    test('http', () {
      const gitUrl = 'http://github.com/dart-lang/pub.git';
      final uri = Uri.parse(gitUrl);
      expect(parseGitUrl(gitUrl), equals(uri.toString()));
    });

    test('https', () {
      const gitUrl = 'https://github.com/dart-lang/pub.git';
      final uri = Uri.parse(gitUrl);
      expect(parseGitUrl(gitUrl), equals(uri.toString()));
    });

    test('git', () {
      const gitUrl = 'git@github.com:dart-lang/pub.git';
      expect(parseGitUrl(gitUrl), equals(gitUrl));
    });
  });
}
