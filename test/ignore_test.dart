// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
import 'dart:collection';
import 'dart:io';

import 'package:test/test.dart';
import 'package:pub/src/ignore.dart';

void main() {
  group('pub', () {
    for (final c in testData) {
      c.paths.forEach(
        (path, expected) => test(
          '${c.name}: Ignore.ignores("$path") == $expected',
          () {
            var hasWarning = false;
            final ignore = Ignore(c.patterns, onInvalidPattern: (a, b) {
              hasWarning = true;
            });
            if (expected != ignore.ignores(path)) {
              if (expected) {
                fail('Expected "$path" to be ignored, it was NOT!');
              }
              fail('Expected "$path" to NOT be ignored, it was IGNORED!');
            }
            expect(hasWarning, c.hasWarning);
          },
        ),
      );
    }
  });

  group('git', () {
    Directory tmp;
    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('package-ignore-test-');
      final ret = await Process.run(
        'git',
        ['init'],
        includeParentEnvironment: false,
        workingDirectory: tmp.path,
      );
      expect(ret.exitCode, equals(0), reason: 'Running "git init" failed');
    });
    tearDownAll(() async {
      await tmp.delete(recursive: true);
      tmp = null;
    });
    for (final c in testData) {
      c.paths.forEach(
        (path, expected) => test(
            '${c.name}: git check-ignore "$path" is ${expected ? 'IGNORED' : 'NOT ignored'}',
            () async {
          final gitIgnore = File.fromUri(tmp.uri.resolve('.gitignore'));
          await gitIgnore.writeAsString(c.patterns.join('\n') + '\n');
          final process = await Process.start(
            'git',
            ['check-ignore', '--no-index', '-z', '--stdin'],
            includeParentEnvironment: false,
            workingDirectory: tmp.path,
          );
          process.stdin.write(path);
          await process.stdin.close();
          final exitCode = await process.exitCode;
          expect(
            exitCode,
            anyOf(0, 1),
            reason: 'Running "git check-ignore" failed',
          );
          final ignored = exitCode == 0;
          if (expected != ignored) {
            if (expected) {
              fail('Expected "$path" to be ignored, it was NOT!');
            }
            fail('Expected "$path" to NOT be ignored, it was IGNORED!');
          }
        }, skip: c.skip),
      );
    }
  });
}

class TestData {
  /// Name of the test case.
  final String name;

  /// Patterns for the test case.
  final List<String> patterns;

  /// Map from path to `true` if ignored by [patterns], and `false` if not
  /// ignored by `patterns`.
  final Map<String, bool> paths;

  /// Allow skipping the git test for a pattern on certain platforms
  final dynamic skip;

  final bool hasWarning;

  TestData(this.name, Iterable<String> patterns, Map<String, bool> paths,
      {this.hasWarning = false, this.skip})
      : patterns = UnmodifiableListView(List.from(patterns)),
        paths = UnmodifiableMapView(
          Map.from(paths),
        );
  TestData.single(String pattern, Map<String, bool> paths,
      {this.hasWarning = false, this.skip})
      : name = '"${pattern.replaceAll('\n', '\\n')}"',
        patterns = UnmodifiableListView([pattern]),
        paths = UnmodifiableMapView(Map.from(paths));
}

final testData = [
  // Simple test case
  TestData('simple', [
    '/.git/',
    '*.o',
  ], {
    '.git/config': true,
    '.git/': true,
    'README.md': false,
    'main.c': false,
    'main.o': true,
  }),
  // Test empty lines
  TestData('empty', [
    ''
  ], {
    'README.md': false,
  }),
  // Test simple patterns
  TestData.single('file.txt', {
    'file.txt': true,
    'other.txt': false,
    'src/file.txt': true,
    '.obj/file.txt': true,
    'sub/folder/file.txt': true,
  }),
  TestData.single('/file.txt', {
    'file.txt': true,
    'other.txt': false,
    'src/file.txt': false,
    '.obj/file.txt': false,
    'sub/folder/file.txt': false,
  }),
  // Test comments and escaping
  TestData.single('#file.txt', {
    'file.txt': false,
    '#file.txt': false,
  }),
  TestData.single(r'\#file.txt', {
    '#file.txt': true,
    'other.txt': false,
    'src/#file.txt': true,
    '.obj/#file.txt': true,
    'sub/folder/#file.txt': true,
  }),
  // Test ! and escaping
  TestData.single(
      '!file.txt',
      {
        'file.txt': false,
        '!file.txt': false,
      },
      skip: Platform.isMacOS == true),
  TestData(
      'negation',
      ['f*', '!file.txt'],
      {
        'file.txt': false,
        '!file.txt': false,
        'filter.txt': true,
      },
      // TODO(sigurdm): Find out why we have issues here.
      skip: Platform.isMacOS == true),
  TestData.single(r'\!file.txt', {
    '!file.txt': true,
    'other.txt': false,
    'src/!file.txt': true,
    '.obj/!file.txt': true,
    'sub/folder/!file.txt': true,
  }),
  // Test trailing spaces and escaping
  TestData.single('file.txt   ', {
    'file.txt': true,
    'other.txt': false,
    'src/file.txt': true,
    '.obj/file.txt': true,
    'sub/folder/file.txt': true,
  }),
  TestData.single(r'file.txt\ \     ', {
    'file.txt  ': true,
    'file.txt': false,
    'other.txt  ': false,
    'src/file.txt  ': true,
    'src/file.txt': false,
    '.obj/file.txt  ': true,
    '.obj/file.txt': false,
    'sub/folder/file.txt  ': true,
    'sub/folder/file.txt': false,
  }),
  // Test ending in a slash or not
  TestData.single('folder/', {
    'file.txt': false,
    'folder': false,
    'folder/': true,
    'folder/file.txt': true,
    'sub/folder/': true,
    'sub/folder': false,
    'sub/file.txt': false,
  }),
  TestData.single('folder.txt/', {
    'file.txt': false,
    'folder.txt': false,
    'folder.txt/': true,
    'folder.txt/file.txt': true,
    'sub/folder.txt/': true,
    'sub/folder.txt': false,
    'sub/file.txt': false,
  }),
  TestData.single('folder', {
    'file.txt': false,
    'folder': true,
    'folder/': true,
    'folder/file.txt': true,
    'sub/folder/': true,
    'sub/folder': true,
    'sub/file.txt': false,
  }),
  TestData.single('folder.txt', {
    'file.txt': false,
    'folder.txt': true,
    'folder.txt/': true,
    'folder.txt/file.txt': true,
    'sub/folder.txt/': true,
    'sub/folder.txt': true,
    'sub/file.txt': false,
  }),
  // Test contains a slash makes it relative root
  TestData.single('/folder/', {
    'file.txt': false,
    'folder': false,
    'folder/': true,
    'folder/file.txt': true,
    'sub/folder/': false,
    'sub/folder': false,
    'sub/file.txt': false,
  }),
  TestData.single('/folder', {
    'file.txt': false,
    'folder': true,
    'folder/': true,
    'folder/file.txt': true,
    'sub/folder/': false,
    'sub/folder': false,
    'sub/file.txt': false,
  }),
  TestData.single('sub/folder/', {
    'file.txt': false,
    'folder': false,
    'folder/': false,
    'folder/file.txt': false,
    'sub/folder/': true,
    'sub/folder/file.txt': true,
    'sub/folder': false,
    'sub/file.txt': false,
  }),
  TestData.single('sub/folder', {
    'file.txt': false,
    'folder': false,
    'folder/': false,
    'folder/file.txt': false,
    'sub/folder/': true,
    'sub/folder/file.txt': true,
    'sub/folder': true,
    'sub/file.txt': false,
  }),
  // Special characters from RegExp that are not special in .gitignore
  for (final c in r'(){}+.^$|'.split('')) ...[
    TestData.single('${c}file.txt', {
      '${c}file.txt': true,
      'file.txt': false,
      'file.txt$c': false,
    }),
    TestData.single('file.txt$c', {
      'file.txt$c': true,
      'file.txt': false,
      '${c}file.txt': false,
    }),
    TestData.single('fi${c}l)e.txt', {
      'fi${c}l)e.txt': true,
      'f${c}il)e.txt': false,
      'fil)e.txt': false,
    }),
    TestData.single('fi${c}l}e.txt', {
      'fi${c}l}e.txt': true,
      'f${c}il}e.txt': false,
      'fil}e.txt': false,
    }),
  ],
  // Special characters from RegExp that are also special in .gitignore
  // can be escaped.
  for (final c in r'[]*?\'.split('')) ...[
    TestData.single('\\${c}file.txt', {
      '${c}file.txt': true,
      'file.txt': false,
      'file.txt$c': false,
    }),
    TestData.single('file.txt\\$c', {
      'file.txt$c': true,
      'file.txt': false,
      '${c}file.txt': false,
    }),
    TestData.single('fi\\${c}l)e.txt', {
      'fi${c}l)e.txt': true,
      'f${c}il)e.txt': false,
      'fil)e.txt': false,
    }),
    TestData.single('fi\\${c}l}e.txt', {
      'fi${c}l}e.txt': true,
      'f${c}il}e.txt': false,
      'fil}e.txt': false,
    }),
  ],
  // Special characters from RegExp can always be escaped
  for (final c in r'()[]{}*+?.^$|\'.split('')) ...[
    TestData.single('\\${c}file.txt', {
      '${c}file.txt': true,
      'file.txt': false,
      'file.txt$c': false,
    }),
    TestData.single('file.txt\\$c', {
      'file.txt$c': true,
      'file.txt': false,
      '${c}file.txt': false,
    }),
    TestData.single('file\\$c.txt', {
      'file$c.txt': true,
      'file.txt': false,
      '${c}file.txt': false,
    }),
  ],
  // Ending in backslash (unescaped)
  TestData.single(
      'file.txt\\',
      {
        'file.txt\\': false,
        'file.txt ': false,
        'file.txt\n': false,
        'file.txt': false,
      },
      hasWarning: true),
  TestData.single(r'file.txt\n', {
    'file.txt\\\n': false,
    'file.txt ': false,
    'file.txt\n': false,
    'file.txt': false,
  }),
  TestData.single(
      '**\\',
      {
        'file.txt\\\n': false,
        'file.txt ': false,
        'file.txt\n': false,
        'file.txt': false,
      },
      hasWarning: true),
  TestData.single(
      '*\\',
      {
        'file.txt\\\n': false,
        'file.txt ': false,
        'file.txt\n': false,
        'file.txt': false,
      },
      hasWarning: true),
  // ? matches anything except /
  TestData.single('?', {
    'f': true,
    'file.txt': false,
  }),
  TestData.single('a?c', {
    'abc': true,
    'abcd': false,
    'a/b': false,
    'ab/': false,
    'folder': false,
    'folder/': false,
    'folder/abc': true,
    'folder/abcd': false,
    'folder/aac': true,
    'abc/': true,
    'abc/file.txt': true,
  }),
  TestData.single('???', {
    'abc': true,
    'abcd': false,
    'a/b': false,
    'ab/': false,
    'folder': false,
    'folder/': false,
    'folder/abc': true,
    'folder/abcd': false,
    'folder/aaa': true,
    'abc/': true,
    'abc/file.txt': true,
  }),
  TestData.single('/???', {
    'abc': true,
    'abcd': false,
    'a/b': false,
    'ab/': false,
    'folder': false,
    'folder/': false,
    'folder/abc': false,
    'folder/abcd': false,
    'folder/aaa': false,
    'abc/': true,
    'abc/file.txt': true,
  }),
  TestData.single('???/', {
    'abc': false,
    'abcd': false,
    'a/b': false,
    'ab/': false,
    'folder': false,
    'folder/': false,
    'folder/abc': false,
    'folder/abcd': false,
    'folder/aaa': false,
    'abc/': true,
    'abc/file.txt': true,
  }),
  TestData.single('???/file.txt', {
    'abc': false,
    'folder': false,
    'folder/': false,
    'folder/abc': false,
    'folder/abcd': false,
    'folder/aaa': false,
    'abc/': false,
    'abc/file.txt': true,
  }),
  // Empty character classes
  TestData.single(
      'a[]c',
      {
        'abc': false,
        'ac': false,
        'a': false,
        'a[]c': false,
        'c': false,
      },
      hasWarning: true),
  TestData.single(
      'a[]',
      {
        'abc': false,
        'ac': false,
        'a': false,
        'a[]': false,
        'c': false,
      },
      hasWarning: true),
  // Invalid character classes
  TestData.single(
      r'a[\]',
      {
        'abc': false,
        'ac': false,
        'a': false,
        'a\\': false,
        'a[]': false,
        'a[': false,
        'a[\\]': false,
        'c': false,
      },
      hasWarning: true),
  TestData.single(
      r'a[\\\]',
      {
        'abc': false,
        'ac': false,
        'a': false,
        'a[]': false,
        'a[': false,
        'a[\\]': false,
        'c': false,
      },
      hasWarning: true),
  // Character classes with special characters
  TestData.single(r'a[\\]', {
    'a': false,
    'ab': false,
    'a[]': false,
    'a[': false,
    'a\\': true,
  }),
  TestData.single(r'a[^b]', {
    'a': false,
    'ab': false,
    'ac': true,
    'a[': true,
    'a\\': true,
  }),
  TestData.single(r'a[!b]', {
    'a': false,
    'ab': false,
    'ac': true,
    'a[': true,
    'a\\': true,
  }),
  TestData.single(r'a[[]', {
    'a': false,
    'ab': false,
    'a[': true,
    'a]': false,
  }),
  TestData.single(r'a[]]', {
    'a': false,
    'ab': false,
    'a[': false,
    'a]': true,
  }),
  TestData.single(r'a[?]', {
    'a': false,
    'ab': false,
    'a??': false,
    'a?': true,
  }),
  // Character classes with characters
  TestData.single(r'a[abc]', {
    'a': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
  }),
  // Character classes with ranges
  TestData.single(r'a[a-c]', {
    'a': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
    'ae': false,
  }),
  TestData.single(r'a[a-cf]', {
    'a': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
    'ae': false,
    'af': true,
  }),
  TestData.single(r'a[a-cx-z]', {
    'a': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
    'ae': false,
    'af': false,
    'ax': true,
    'ay': true,
    'az': true,
  }),
  // Character classes with weird-ranges
  TestData.single(r'a[a-c-e]', {
    'a': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
    'af': false,
    'ae': true,
    'a-': true,
  }),
  TestData.single(r'a[--0]', {
    'a': false,
    'a-': true,
    'a.': true,
    'a0': true,
    'a1': false,
  }),
  TestData.single(r'a[+--]', {
    'a': false,
    'a-': true,
    'a+': true,
    'a,': true,
    'a0': false,
  }),
  TestData.single(r'a[a-c]', {
    'a': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
    'a-': false,
  }),
  TestData.single(r'a[\a-c]', {
    'a': false,
    'a\\': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
    'a-': false,
  }),
  TestData.single(r'a[a-\c]', {
    'a': false,
    'a\\': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
    'a-': false,
  }),
  TestData.single(r'a[\a-\c]', {
    'a': false,
    'a\\': false,
    'aa': true,
    'ab': true,
    'ac': true,
    'ad': false,
    'a-': false,
  }),
  TestData.single(r'a[\a\-\c]', {
    'a': false,
    'a\\': false,
    'aa': true,
    'ab': false,
    'a-': true,
    'ac': true,
    'ad': false,
  }),
  // Character classes with dashes
  TestData.single(r'a[-]', {
    'a-': true,
    'a': false,
  }),
  TestData.single(r'a[a-]', {
    'a-': true,
    'aa': true,
    'ab': false,
  }),
  TestData.single(r'a[-a]', {
    'a-': true,
    'aa': true,
    'ab': false,
  }),
  // TODO: test slashes in character classes
  // Test **, *, [, and [...] cases
  TestData.single('x[a-c-e]', {
    'xa': true,
    'xb': true,
    'xc': true,
    'cd': false,
    'xe': true,
    'x-': true,
  }),
  TestData.single('*', {
    'file.txt': true,
    'other.txt': true,
    'src/file.txt': true,
    '.obj/file.txt': true,
    'sub/folder/file.txt': true,
  }),
  TestData.single('f*', {
    'file.txt': true,
    'otherf.txt': false,
    'src/file.txt': true,
    'folder/other.txt': true,
    'sub/folder/file.txt': true,
  }),
  TestData.single('*f', {
    'file.txt': false,
    'otherf.txt': false,
    'otherf.paf': true,
    'src/file.txt': false,
    'folder/other.txt': false,
    'sub/folderf/file.txt': true,
  }),
  TestData.single('sub/**/f*', {
    'file.txt': false,
    'otherf.txt': false,
    'other.paf': false,
    'src/file.txt': false,
    'folder/other.txt': false,
    'sub/file.txt': true,
    'sub/f.txt': true,
    'sub/pile.txt': false,
    'sub/other.paf': false,
    'sub/folder/file.txt': true,
    'sub/folder/': true,
    'sub/folder/pile.txt': true,
    'sub/folder/other.paf': true,
    'sub/bolder/': false,
    'sub/bolder/file.txt': true,
    'sub/bolder/pile.txt': false,
    'sub/bolder/other.paf': false,
    'subblob/file.txt': false,
  }),
  TestData.single('sub/**/', {
    'file.txt': false,
    'otherf.txt': false,
    'other.paf': false,
    'src/file.txt': false,
    'folder/other.txt': false,
    'sub/file.txt': false,
    'sub/f.txt': false,
    'sub/pile.txt': false,
    'sub/other.paf': false,
    'sub/folder/': true,
    'sub/sub/folder/': true,
    'sub/folder/file.txt': true,
    'sub/folder/pile.txt': true,
    'sub/folder/other.paf': true,
    'sub/bolder/': true,
    'sub/': false,
    'sub/bolder/file.txt': true,
    'sub/bolder/pile.txt': true,
    'sub/bolder/other.paf': true,
    'subblob/file.txt': false,
  }),
  TestData.single('**/bolder/', {
    'file.txt': false,
    'otherf.txt': false,
    'other.paf': false,
    'src/file.txt': false,
    'sub/folder/bolder': false,
    'sub/folder/other.paf': false,
    'sub/bolder/': true,
    'sub/': false,
    'bolder/': true,
    'bolder': false,
    'sub/bolder/file.txt': true,
    'sub/bolder/pile.txt': true,
    'sub/bolder/other.paf': true,
    'subblob/file.txt': false,
  }),
];
