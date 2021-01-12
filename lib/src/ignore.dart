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

/// A set of ignore rules representing a hierrchy of ignore files.
///
/// An [Ignore] instance holds [`.gitignore` rules][1] relative to given paths,
/// and allows testing if a given path is ignored.
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
  final Map<String, List<GitIgnoreRule>> _rules;

  // True if no rule-files have been added.
  bool get isEmpty => _rules.isEmpty;

  /// Create an [Ignore] instance with a set of [`.gitignore` compatible][1]
  /// patterns.
  ///
  /// Each value in [patterns] will be interpreted as one or more lines from
  /// a `.gitignore` file, in compliance with the [`.gitignore` manual page][1].
  ///
  /// The keys of 'pattern' are the directories to intpret the rules relative
  /// to. The root should be the empty string, and sub-directories are separated
  /// by '/' (but no final '/').
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
  ///   final ignore = Ignore({'': [
  ///     // You can pass an entire .gitignore file as a single string.
  ///     // You can also pass it as a list of lines, or both.
  ///     '''
  /// # Comment in a .gitignore file
  /// obj/
  /// *.o
  /// !main.o
  ///   '''
  ///   }]);
  ///
  ///   print(ignore.ignores('obj/README.md')); // true
  ///   print(ignore.ignores('lib.o')); // false
  ///   print(ignore.ignores('main.o')); // false
  /// }
  /// ```
  ///
  /// [1]: https://git-scm.com/docs/gitignore
  /// [2]: https://git-scm.com/docs/git-config#Documentation/git-config.txt-coreignoreCase
  Ignore(
    Map<String, Iterable<String>> patterns, {
    bool ignoreCase = false,
    void Function(String pattern, FormatException exception) onInvalidPattern,
  }) : _rules = parseIgnorePatterns(patterns, ignoreCase,
            onInvalidPattern: onInvalidPattern);

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
    if (_rules.isEmpty) {
      return false;
    }
    bool ignoresSubpath(String path) {
      bool testRulesForPrefix(String prefix) {
        final rules = _rules[prefix];

        if (rules != null) {
          // Test the rules against the rest of the path.
          final l = prefix == '' ? 0 : prefix.length + 1;
          final suffix = path.substring(l);
          // Test patterns in reverse. The negativity of the last
          // matching pattern decides the fate of the path.
          for (final r in rules.reversed) {
            if (r.pattern.hasMatch(suffix)) {
              return !r.negative;
            }
          }
        }
        return null;
      }

      // Iterate over all subpaths to find relevant rules.
      for (var index = path.lastIndexOf('/');
          index != -1;
          index = path.lastIndexOf('/', index - 1)) {
        final result = testRulesForPrefix(path.substring(0, index));
        if (result != null) return result;
      }
      return testRulesForPrefix('') == true;
    }

    for (var slashIndex = path.indexOf('/');
        slashIndex != -1;
        slashIndex = path.indexOf('/', slashIndex + 1)) {
      if (ignoresSubpath(path.substring(0, slashIndex + 1))) {
        // If a folder above [path] is ignored the pattern cannot be un-ignored.
        return true;
      }
    }
    return ignoresSubpath(path);
  }
}

class GitIgnoreParseResult {
  // The parsed pattern.
  final String pattern;

  // The resulting matching rule. `null` if the pattern was empty or invalid.
  final GitIgnoreRule rule;

  // An invalid pattern is also considered empty.
  bool get empty => rule == null;
  bool get valid => exception == null;

  // For invalid patterns this contains a description of the problem.
  final FormatException exception;

  GitIgnoreParseResult(this.pattern, this.rule) : exception = null;
  GitIgnoreParseResult.invalid(this.pattern, this.exception) : rule = null;
  GitIgnoreParseResult.empty(this.pattern)
      : rule = null,
        exception = null;
}

class GitIgnoreRule {
  /// A regular expression that represents this rule.
  final RegExp pattern;
  final bool negative;

  /// The String this pattern was generated from.
  final String original;

  GitIgnoreRule(this.pattern, this.negative, this.original);

  @override
  String toString() {
    // TODO: implement toString
    return '$original -> $pattern';
  }
}

/// [onInvalidPattern] can be used to handle parse failures. If
/// [onInvalidPattern] is `null` invalid patterns are ignored.
Map<String, List<GitIgnoreRule>> parseIgnorePatterns(
    Map<String, Iterable<String>> patternsHierarchy, bool ignoreCase,
    {void Function(String pattern, FormatException exception)
        onInvalidPattern}) {
  ArgumentError.checkNotNull(patternsHierarchy, 'patterns');
  ArgumentError.checkNotNull(ignoreCase, 'ignoreCase');
  if (patternsHierarchy.values.contains(null)) {
    throw ArgumentError.value(
        patternsHierarchy, 'patterns', 'may not contain null');
  }

  return patternsHierarchy.map((directory, patterns) {
    final parseResults = patterns
        .map((s) => s.split('\n'))
        .expand((e) => e)
        .map((pattern) => parseIgnorePattern(pattern, ignoreCase));
    if (onInvalidPattern != null) {
      for (final invalidResult
          in parseResults.where((result) => !result.valid)) {
        onInvalidPattern(invalidResult.pattern, invalidResult.exception);
      }
    }
    return MapEntry(directory,
        parseResults.where((r) => !r.empty).map((r) => r.rule).toList());
  });
}

GitIgnoreParseResult parseIgnorePattern(String pattern, bool ignoreCase,
    {source}) {
  // Check if patterns is a comment
  if (pattern.startsWith('#')) {
    return GitIgnoreParseResult.empty(pattern);
  }
  var first = 0;
  var end = pattern.length;

  // Detect negative patterns
  final negative = pattern.startsWith('!');
  if (negative) {
    first++;
  }

  // Remove trailing whitespace unless escaped
  while (end != 0 &&
      pattern[end - 1] == ' ' &&
      (end == 1 || pattern[end - 2] != '\\')) {
    end--;
  }
  // Empty patterns match nothing.
  if (first == end) return GitIgnoreParseResult.empty(pattern);

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
            expr += '.*';
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
        return GitIgnoreParseResult.invalid(
          pattern,
          FormatException(
              'Pattern "$pattern" had an invalid `[a-b]` style character range',
              source,
              current),
        );
      }
      expr += '[$characterRange]';
    } else if (nextChar == '\\') {
      // Escapes
      final escaped = peekChar();
      if (escaped == null) {
        return GitIgnoreParseResult.invalid(
          pattern,
          FormatException(
              'Pattern "$pattern" end of pattern inside character escape.',
              source,
              current),
        );
      }
      expr += RegExp.escape(escaped);
      current++;
    } else {
      if (nextChar == '/') {
        if (current - 1 != first && current != end) {
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
  if (matchesDirectoriesOnly) {
    expr = '$expr/\$';
  } else {
    expr = '$expr/?\$';
    // expr = '$expr\$';
  }
  try {
    return GitIgnoreParseResult(
        pattern,
        GitIgnoreRule(
            RegExp(expr, caseSensitive: ignoreCase), negative, pattern));
  } on FormatException catch (e) {
    throw AssertionError(
        'Created broken expression "$expr" from ignore pattern "$pattern" -> $e');
  }
}
