// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:io';

import 'package:pub/src/ignore.dart';
import 'package:test/test.dart';

void main() {
  group('Ignore.ignores', () {
    // just for sanity checking
    test('simple case', () {
      final ig = Ignore(['*.dart']);

      expect(ig.ignores('file.dart'), isTrue);
      expect(ig.ignores('lib/file.dart'), isTrue);
      expect(ig.ignores('README.md'), isFalse);
    });
  });

  group('pub', () {
    void _testIgnorePath(
      TestData c,
      String path,
      bool expected,
      bool ignoreCase,
    ) {
      final casing = 'with ignoreCase = $ignoreCase';
      test('${c.name}: Ignore.ignores("$path") == $expected $casing', () {
        var hasWarning = false;
        final pathWithoutSlash =
            path.endsWith('/') ? path.substring(0, path.length - 1) : path;

        Iterable<String> listDir(String dir) {
          // List the next part of path:
          if (dir == pathWithoutSlash) return [];
          final nextSlash = path.indexOf('/', dir == '.' ? 0 : dir.length + 1);
          return [path.substring(0, nextSlash == -1 ? path.length : nextSlash)];
        }

        Ignore ignoreForDir(String dir) => c.patterns[dir] == null
            ? null
            : Ignore(
                c.patterns[dir],
                onInvalidPattern: (_, __) => hasWarning = true,
                ignoreCase: ignoreCase,
              );

        bool isDir(String candidate) =>
            candidate == '.' ||
            path.length > candidate.length && path[candidate.length] == '/';

        final r = Ignore.listFiles(
          beneath: pathWithoutSlash,
          includeDirs: true,
          listDir: listDir,
          ignoreForDir: ignoreForDir,
          isDir: isDir,
        );
        if (expected) {
          expect(r, isEmpty,
              reason: 'Expected "$path" to be ignored, it was NOT!');
        } else {
          expect(r, [pathWithoutSlash],
              reason: 'Expected "$path" to NOT be ignored, it was IGNORED!');
        }

        // Also test that the logic of walking the tree works.
        final r2 = Ignore.listFiles(
            includeDirs: true,
            listDir: listDir,
            ignoreForDir: ignoreForDir,
            isDir: isDir);
        if (expected) {
          expect(r2, isNot(contains(pathWithoutSlash)),
              reason: 'Expected "$path" to be ignored, it was NOT!');
        } else {
          expect(r2, contains(pathWithoutSlash),
              reason: 'Expected "$path" to NOT be ignored, it was IGNORED!');
        }
        expect(hasWarning, c.hasWarning);
      });
    }

    for (final c in testData) {
      c.paths.forEach((path, expected) {
        if (c.ignoreCase == null) {
          _testIgnorePath(c, path, expected, false);
          _testIgnorePath(c, path, expected, true);
        } else {
          _testIgnorePath(c, path, expected, c.ignoreCase);
        }
      });
    }
  });

  ProcessResult runGit(List<String> args, {String workingDirectory}) {
    final executable = Platform.isWindows ? 'cmd' : 'git';
    args = Platform.isWindows ? ['/c', 'git', ...args] : args;
    return Process.runSync(executable, args,
        workingDirectory: workingDirectory);
  }

  group('git', () {
    Directory tmp;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('package-ignore-test-');

      final ret = runGit(['init'], workingDirectory: tmp.path);
      expect(ret.exitCode, equals(0),
          reason:
              'Running "git init" failed. StdErr: ${ret.stderr} StdOut: ${ret.stdout}');
    });

    tearDownAll(() async {
      await tmp.delete(recursive: true);
      tmp = null;
    });

    tearDown(() async {
      runGit(['clean', '-f', '-d', '-x'], workingDirectory: tmp.path);
    });

    void _testIgnorePath(
      TestData c,
      String path,
      bool expected,
      bool ignoreCase,
    ) {
      final casing = 'with ignoreCase = $ignoreCase';
      final result = expected ? 'IGNORED' : 'NOT ignored';
      test('${c.name}: git check-ignore "$path" is $result $casing', () async {
        expect(
          runGit(
            ['config', '--local', 'core.ignoreCase', ignoreCase.toString()],
            workingDirectory: tmp.path,
          ).exitCode,
          anyOf(0, 1),
          reason: 'Running "git config --local core.ignoreCase ..." failed',
        );

        for (final directory in c.patterns.keys) {
          final resolvedDirectory =
              directory == '' ? tmp.uri : tmp.uri.resolve(directory + '/');
          Directory.fromUri(resolvedDirectory).createSync(recursive: true);
          final gitIgnore =
              File.fromUri(resolvedDirectory.resolve('.gitignore'));
          gitIgnore.writeAsStringSync(
            c.patterns[directory].join('\n') + '\n',
          );
        }
        final process = runGit(
            ['-C', tmp.path, 'check-ignore', '--no-index', path],
            workingDirectory: tmp.path);
        expect(process.exitCode, anyOf(0, 1),
            reason: 'Running "git check-ignore" failed');
        final ignored = process.exitCode == 0;
        if (expected != ignored) {
          if (expected) {
            fail('Expected "$path" to be ignored, it was NOT!');
          }
          fail('Expected "$path" to NOT be ignored, it was IGNORED!');
        }
      },
          skip: Platform.isMacOS || // System `git` on mac has issues...
              c.skipOnWindows && Platform.isWindows);
    }

    for (final c in testData) {
      c.paths.forEach((path, expected) {
        if (c.ignoreCase == null) {
          _testIgnorePath(c, path, expected, false);
          _testIgnorePath(c, path, expected, true);
        } else {
          _testIgnorePath(c, path, expected, c.ignoreCase);
        }
      });
    }
  });
}

class TestData {
  /// Name of the test case.
  final String name;

  /// Patterns for the test case.
  final Map<String, List<String>> patterns;

  /// Map from path to `true` if ignored by [patterns], and `false` if not
  /// ignored by `patterns`.
  final Map<String, bool> paths;

  final bool hasWarning;

  /// Many of the tests don't play well on windows. Simply skip them.
  final bool skipOnWindows;

  /// Test with `core.ignoreCase` set to `true`, `false` or both (if `null`).
  final bool ignoreCase;

  TestData(
    this.name,
    this.patterns,
    this.paths, {
    this.hasWarning = false,
    this.skipOnWindows = false,
    this.ignoreCase,
  });

  TestData.single(
    String pattern,
    this.paths, {
    this.hasWarning = false,
    this.skipOnWindows = false,
    this.ignoreCase,
  })  : name = '"${pattern.replaceAll('\n', '\\n')}"',
        patterns = {
          '.': [pattern]
        };
}

final testData = [
  // Simple test case
  TestData('simple', {
    '.': [
      '/.git/',
      '*.o',
    ]
  }, {
    '.git/config': true,
    '.git/': true,
    'README.md': false,
    'main.c': false,
    'main.o': true,
  }),
  // Test empty lines
  TestData('empty', {
    '.': ['']
  }, {
    'README.md': false,
  }),
  // Patterns given in multiple lines with comments
  TestData('multiple lines LF', {
    '.': [
      '#comment\n/.git/ \n*.o\n',
      // Using CR CR LF doesn't work
      '#comment\n*.md\r\r\n',
      // Tab is not ignored
      '#comment\nLICENSE\t\n',
      // Trailing comments not allowed
      '#comment\nLICENSE  # ignore license\n',
    ]
  }, {
    '.git/config': true,
    '.git/': true,
    'README.md': false,
    'LICENSE': false,
    'main.c': false,
    'main.o': true,
  }),
  TestData('multiple lines CR LF', {
    '.': [
      '#comment\r\n/.git/ \r\n*.o\r\n',
      // Using CR CR LF doesn't work
      '#comment\r\n*.md\r\r\n',
      // Tab is not ignored
      '#comment\r\nLICENSE\t\r\n',
      // Trailing comments not allowed
      '#comment\r\nLICENSE  # ignore license\r\n',
    ]
  }, {
    '.git/config': true,
    '.git/': true,
    'README.md': false,
    'LICENSE': false,
    'main.c': false,
    'main.o': true,
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
  TestData.single('!file.txt', {
    'file.txt': false,
    '!file.txt': false,
  }),
  TestData(
    'negation',
    {
      '.': ['f*', '!file.txt']
    },
    {
      'file.txt': false,
      '!file.txt': false,
      'filter.txt': true,
    },
  ),
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
    TestData.single(
        '${c}file.txt',
        {
          '${c}file.txt': true,
          'file.txt': false,
          'file.txt$c': false,
        },
        skipOnWindows: c == '^' || c == '|'),
    TestData.single(
        'file.txt$c',
        {
          'file.txt$c': true,
          'file.txt': false,
          '${c}file.txt': false,
        },
        skipOnWindows: c == '^' || c == '|'),
    TestData.single(
        'fi${c}l)e.txt',
        {
          'fi${c}l)e.txt': true,
          'f${c}il)e.txt': false,
          'fil)e.txt': false,
        },
        skipOnWindows: c == '^' || c == '|'),
    TestData.single(
        'fi${c}l}e.txt',
        {
          'fi${c}l}e.txt': true,
          'f${c}il}e.txt': false,
          'fil}e.txt': false,
        },
        skipOnWindows: c == '^' || c == '|'),
  ],
  // Special characters from RegExp that are also special in .gitignore
  // can be escaped.
  for (final c in r'[]*?\'.split('')) ...[
    TestData.single(
        '\\${c}file.txt',
        {
          '${c}file.txt': true,
          'file.txt': false,
          'file.txt$c': false,
        },
        skipOnWindows: c == r'\'),
    TestData.single(
        'file.txt\\$c',
        {
          'file.txt$c': true,
          'file.txt': false,
          '${c}file.txt': false,
        },
        skipOnWindows: c == r'\'),
    TestData.single(
        'fi\\${c}l)e.txt',
        {
          'fi${c}l)e.txt': true,
          'f${c}il)e.txt': false,
          'fil)e.txt': false,
        },
        skipOnWindows: c == r'\'),
    TestData.single(
        'fi\\${c}l}e.txt',
        {
          'fi${c}l}e.txt': true,
          'f${c}il}e.txt': false,
          'fil}e.txt': false,
        },
        skipOnWindows: c == r'\'),
  ],
  // Special characters from RegExp can always be escaped
  for (final c in r'()[]{}*+?.^$|\'.split('')) ...[
    TestData.single(
        '\\${c}file.txt',
        {
          '${c}file.txt': true,
          'file.txt': false,
          'file.txt$c': false,
        },
        skipOnWindows: c == '^' || c == '|' || c == r'\'),
    TestData.single(
        'file.txt\\$c',
        {
          'file.txt$c': true,
          'file.txt': false,
          '${c}file.txt': false,
        },
        skipOnWindows: c == '^' || c == '|' || c == r'\'),
    TestData.single(
        'file\\$c.txt',
        {
          'file$c.txt': true,
          'file.txt': false,
          '${c}file.txt': false,
        },
        skipOnWindows: c == '^' || c == '|' || c == r'\'),
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
      hasWarning: true,
      skipOnWindows: true),
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
      hasWarning: true,
      skipOnWindows: true),
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
      hasWarning: true,
      skipOnWindows: true),
  // Character classes with special characters
  TestData.single(
      r'a[\\]',
      {
        'a': false,
        'ab': false,
        'a[]': false,
        'a[': false,
        'a\\': true,
      },
      skipOnWindows: true),
  TestData.single(
      r'a[^b]',
      {
        'a': false,
        'ab': false,
        'ac': true,
        'a[': true,
        'a\\': true,
      },
      skipOnWindows: true),
  TestData.single(
      r'a[!b]',
      {
        'a': false,
        'ab': false,
        'ac': true,
        'a[': true,
        'a\\': true,
      },
      skipOnWindows: true),
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
  TestData.single('sub/', {
    'sub/': true,
    'mop/': false,
    'sup': false,
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
  TestData('ignores in subfolders only target those', {
    '.': ['a.txt'],
    'folder': ['b.txt'],
    'folder/sub': ['c.txt'],
  }, {
    'a.txt': true,
    'b.txt': false,
    'c.txt': false,
    'folder/a.txt': true,
    'folder/b.txt': true,
    'folder/c.txt': false,
    'folder/sub/a.txt': true,
    'folder/sub/b.txt': true,
    'folder/sub/c.txt': true,
  }),
  TestData('Cannot negate folders that were excluded', {
    '.': ['sub/', '!sub/foo.txt']
  }, {
    'sub/a.txt': true,
    'sub/foo.txt': true,
  }),
  TestData('Can negate the exclusion of folders', {
    '.': ['*.txt', 'sub', '!sub', '!foo.txt'],
  }, {
    'sub/a.txt': true,
    'sub/foo.txt': false,
  }),
  TestData('Can negate the exclusion of folders 2', {
    '.': ['sub/', '*.txt'],
    'folder': ['!sub/', '!foo.txt']
  }, {
    'folder/sub/a.txt': true,
    'folder/sub/foo.txt': false,
    'folder/foo.txt': false,
    'folder/a.txt': true,
  }),

  // Case sensitivity
  TestData(
    'simple',
    {
      '.': [
        '/.git/',
        '*.o',
      ]
    },
    {
      '.git/config': true,
      '.git/': true,
      'README.md': false,
      'main.c': false,
      'main.o': true,
      'main.O': false,
    },
    ignoreCase: false,
  ),
  // Test simple patterns
  TestData.single(
    'file.txt',
    {
      'file.TXT': false,
      'file.txT': false,
      'file.txt': true,
      'other.txt': false,
      'src/file.txt': true,
      '.obj/file.txt': true,
      'sub/folder/file.txt': true,
      'src/file.TXT': false,
      '.obj/file.TXT': false,
      'sub/folder/file.TXT': false,
    },
    ignoreCase: false,
  ),

  // Case insensitivity
  TestData(
    'simple',
    {
      '.': [
        '/.git/',
        '*.o',
      ]
    },
    {
      '.git/config': true,
      '.git/': true,
      'README.md': false,
      'main.c': false,
      'main.o': true,
      'main.O': true,
    },
    ignoreCase: true,
  ),
  TestData.single(
    'file.txt',
    {
      'file.TXT': true,
      'file.txT': true,
      'file.txt': true,
      'other.txt': false,
      'src/file.txt': true,
      '.obj/file.txt': true,
      'sub/folder/file.txt': true,
      'src/file.TXT': true,
      '.obj/file.TXT': true,
      'sub/folder/file.TXT': true,
    },
    ignoreCase: true,
  ),
];
