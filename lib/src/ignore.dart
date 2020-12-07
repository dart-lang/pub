// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An [Ignore] filter compatible with `.gitignore`.
///
/// An [Ignore] instance holds a set of [`.gitignore` rules][1], and allows
/// testing if a given path is ignored.
///
/// **Example**:
/// ```dart
/// import 'package:ignore/ignore.dart';
///
/// void main() {
///   final ignore = Ignore([
///     '*.o',
///   ]);
///
///   print(ignore.ignores('main.o')); // true
///   print(ignore.ignores('main.c')); // false
/// }
/// ```
///
/// [1]: https://git-scm.com/docs/gitignore

import 'package:meta/meta.dart';

/// A set of ignore rules.
///
/// An [Ignore] instance holds a set of [`.gitignore` rules][1], and allows
/// testing if a given path is ignored.
///
/// **Example**:
/// ```dart
/// import 'package:ignore/ignore.dart';
///
/// void main() {
///   final ignore = Ignore([
///     '*.o',
///   ]);
///
///   print(ignore.ignores('main.o')); // true
///   print(ignore.ignores('main.c')); // false
/// }
/// ```
///
/// [1]: https://git-scm.com/docs/gitignore
@sealed
class Ignore {
  final List<GitIgnoreRule> _rules;

  /// Create an [Ignore] instance with a set of [`.gitignore` compatible][1]
  /// patterns.
  ///
  /// Each pattern in [patterns] will be interpreted as one or more lines from
  /// a `.gitignore` file, in compliance with the [`.gitignore` manual page][1].
  ///
  /// If [ignoreCase] is `true`, patterns will be case-insensitive. By default
  /// `git` is case-sensitive. But case insensitivity can be enabled when a
  /// repository is created, or by configuration option, see
  /// [`core.ignoreCase` documentation][2] for details.
  ///
  /// **Example**:
  /// ```dart
  /// import 'package:ignore/ignore.dart';
  /// void main() {
  ///   final ignore = Ignore([
  ///     // You can pass an entire .gitignore file as a single string.
  ///     // You can also pass it as a list of lines, or both.
  ///     '''
  /// # Comment in a .gitignore file
  /// obj/
  /// *.o
  /// !main.o
  ///   '''
  ///   ]);
  ///
  ///   print(ignore.ignores('obj/README.md')); // true
  ///   print(ignore.ignores('lib.o')); // false
  ///   print(ignore.ignores('main.o')); // false
  /// }
  /// ```
  ///
  /// [1]: https://git-scm.com/docs/gitignore
  /// [2]: https://git-scm.com/docs/git-config#Documentation/git-config.txt-coreignoreCase
  Ignore(Iterable<String> patterns, {bool ignoreCase = false})
      : _rules = parseIgnorePatterns(patterns, ignoreCase);

  /// Returns `true` if [path] is ignored by the patterns used to create this
  /// [Ignore] instance.
  ///
  /// The [path] must be a relative path, not starting with `./`, `../`, and
  /// must end in slash (`/`) if it is directory.
  ///
  /// **Example**:
  /// ```dart
  /// import 'package:ignore/ignore.dart';
  ///
  /// void main() {
  ///   final ignore = Ignore([
  ///     '*.o',
  ///   ]);
  ///
  ///   print(ignore.ignores('main.o')); // true
  ///   print(ignore.ignores('main.c')); // false
  ///   print(ignore.ignores('lib/')); // false
  ///   print(ignore.ignores('lib/helper.o')); // true
  ///   print(ignore.ignores('lib/helper.c')); // false
  /// }
  /// ```
  bool ignores(String path) {
    ArgumentError.checkNotNull(path, 'path');
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must be not empty');
    }
    if (path.startsWith('/') ||
        path.startsWith('./') ||
        path.startsWith('../') ||
        path == '.' ||
        path == '..') {
      throw ArgumentError.value(
        path,
        'path',
        'must be relative, and not start with "./", "../"',
      );
    }

    // for (final p in _parentFolders(path).followedBy([path])) {
    var ignored = false;
    for (final r in _rules) {
      if (ignored == r.negative && r.pattern.hasMatch(path)) {
        ignored = !r.negative;
      }
    }
    return ignored;
  }
}

class GitIgnoreRule {
  final String original;
  final RegExp pattern;
  final bool negative;
  GitIgnoreRule(this.original, this.pattern, this.negative);
}

List<GitIgnoreRule> parseIgnorePatterns(
  Iterable<String> patterns,
  bool ignoreCase,
) {
  ArgumentError.checkNotNull(patterns, 'patterns');
  ArgumentError.checkNotNull(ignoreCase, 'ignoreCase');
  if (patterns.contains(null)) {
    throw ArgumentError.value(patterns, 'patterns', 'may not contain null');
  }
  return patterns
      .map((s) => s.split('\n'))
      .expand((e) => e)
      .map((pattern) => parseIgnorePattern(pattern, ignoreCase))
      .where((r) => r != null)
      .toList();
}

GitIgnoreRule parseIgnorePattern(String pattern, bool ignoreCase) {
  // Check if patterns is a comment
  if (pattern.startsWith('#')) {
    return null;
  }
  var first = 0;
  var end = pattern.length;

  // Detect negative patterns
  final negative = pattern.startsWith('!');
  if (negative) {
    first++;
  }
  // Remove escape for # and !
  if (pattern.startsWith(r'\#') || pattern.startsWith(r'\!')) {
    first++;
  }
  // Remove trailing whitespace unless escaped
  while (end != 0 &&
      pattern[end - 1] == ' ' &&
      (end == 1 || pattern[end - 2] != '\\')) {
    end--;
  }
  // Empty patterns match nothing.
  if (first == end) return null;

  var current = first;
  String peekChar() => current >= end ? null : pattern[current];

  var expr = '';

  // Parses the inside of a [] range. Returns the value as a RegExp character
  // range, or null if the pattern was broken.
  String parseCharacterRange() {
    var characterRange = '';
    var first = true;
    for (;;) {
      final nextChar = peekChar();
      if (nextChar == null) {
        return null;
      }
      current++;
      if (nextChar == '\\') {
        final escaped = peekChar();
        if (escaped == null) {
          return null;
        }
        current++;

        characterRange += escaped == '-' ? r'\-' : RegExp.escape(escaped);
      } else if (nextChar == '!' && first) {
        characterRange += '^';
      } else if (nextChar == ']' && first) {
        characterRange += RegExp.escape(nextChar);
      } else if (nextChar == ']') {
        assert(!first);
        return characterRange;
      } else {
        characterRange += nextChar;
      }
      first = false;
    }
  }

  var relativeToPath = false;
  var matchesDirectoriesOnly = false;

  // slashes have different significance depending on where they are in
  // the String. Handle that here.
  void handleSlash() {
    if (current == end) {
      // A slash at the end makes us only match directories.
      matchesDirectoriesOnly = true;
    } else {
      // A slash anywhere else makes the pattern relative anchored at the
      // current path.
      relativeToPath = true;
    }
  }

  for (;;) {
    final nextChar = peekChar();
    if (nextChar == null) break;
    current++;
    if (nextChar == '*') {
      if (peekChar() == '*') {
        // Handle '**'
        current++;
        if (peekChar() == '/') {
          current++;
          if (current == end) {
            expr += '.*/';
          } else {
            // Match nothing or a path followed by '/'
            expr += '(?:(?:)|(?:.*/))';
          }
          // Handle the side effects of seeing a slash.
          handleSlash();
        } else {
          expr += '.*';
        }
      } else {
        // Handle a single '*'
        expr += '[^/]*';
      }
    } else if (nextChar == '?') {
      // Handle '?'
      expr += '[^/]';
    } else if (nextChar == '[') {
      // Character ranges
      final characterRange = parseCharacterRange();
      if (characterRange == null) {
        return null;
      }
      expr += '[$characterRange]';
    } else if (nextChar == '\\') {
      // Escapes
      final escaped = peekChar();
      if (escaped == null) {
        return null;
      }
      expr += RegExp.escape(escaped);
      current++;
    } else {
      if (nextChar == '/') {
        if (current - 1 != first) {
          // If slash appears in the beginning we don't want it manifest in the
          // regexp.
          expr += '/';
        }
        handleSlash();
      } else {
        expr += RegExp.escape(nextChar);
      }
    }
  }
  if (relativeToPath) {
    expr = '^$expr';
  } else {
    expr = '(?:^|/)$expr';
  }
  if (!matchesDirectoriesOnly) {
    expr = '$expr(?:\$|/)';
  }
  try {
    return GitIgnoreRule(
        pattern, RegExp(expr, caseSensitive: ignoreCase), negative);
  } on FormatException catch (e) {
    throw AssertionError(
        'Created broken expression "$expr" from ignore pattern "$pattern" -> $e');
  }
}
