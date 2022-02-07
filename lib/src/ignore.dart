// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Implements an [Ignore] filter compatible with `.gitignore`.
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
/// For a generic walk of a file-hierarchy with ignore files at all levels see
/// [Ignore.listFiles].
///
/// [1]: https://git-scm.com/docs/gitignore
import 'package:meta/meta.dart';

/// A set of ignore rules representing a single ignore file.
///
/// An [Ignore] instance holds [`.gitignore` rules][1] relative to a given path.
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
  final List<_IgnoreRule> _rules;

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
  /// If [onInvalidPattern] is passed, it will be called with a
  /// [FormatException] describing the problem. The exception will have [source]
  /// as source.
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
    List<String> patterns, {
    bool ignoreCase = false,
    void Function(String pattern, FormatException exception)? onInvalidPattern,
  }) : _rules = _parseIgnorePatterns(
          patterns,
          ignoreCase,
          onInvalidPattern: onInvalidPattern,
        ).toList(growable: false);

  /// Returns `true` if [path] is ignored by the patterns used to create this
  /// [Ignore] instance, assuming those patterns are placed at `.`.
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
    final pathWithoutSlash =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    return listFiles(
      beneath: pathWithoutSlash,
      includeDirs: true,
      // because we are listing below pathWithoutSlash
      listDir: (dir) {
        // List the next part of path:
        if (dir == pathWithoutSlash) return [];
        final startOfNext = dir.isEmpty ? 0 : dir.length + 1;
        final nextSlash = path.indexOf('/', startOfNext);
        return [path.substring(startOfNext, nextSlash)];
      },
      ignoreForDir: (dir) => dir == '.' || dir.isEmpty ? this : null,
      isDir: (candidate) =>
          candidate == '.' ||
          candidate.isEmpty ||
          path.length > candidate.length && path[candidate.length] == '/',
    ).isEmpty;
  }

  /// Returns all the files in the tree under (and including) [beneath] not
  /// ignored by ignore-files from [root] and down.
  ///
  /// Represents paths normalized  using '/' as directory separator. The empty
  /// relative path is '.', no '..' are allowed.
  ///
  /// [beneath] must start with [root] and even if it is a directory it should not
  /// end with '/', if [beneath] is not provided, everything under root is
  /// included.
  ///
  /// [listDir] should enumerate the immediate contents of a given directory,
  /// returning paths including [root].
  ///
  /// [isDir] should return true if the argument is a directory. It will only be
  /// queried with file-names under (and including) [beneath]
  ///
  /// [ignoreForDir] should retrieve the ignore rules for a single directory
  /// or return `null` if there is no ignore rules.
  ///
  /// If [includeDirs] is true non-ignored directories will be included in the
  /// result (including beneath).
  ///
  /// This example program lists all files under second argument that are
  /// not ignored by .gitignore files from first argument and below:
  ///
  /// ```dart
  /// import 'dart:io';
  /// import 'package:path/path.dart' as p;
  /// import 'package:pub/src/ignore.dart';
  ///
  /// void main(List<String> args) {
  ///   var root = p.normalize(args[0]);
  ///   if (root == '.') root = '';
  ///   var beneath = args.length > 1 ? p.normalize(args[1]) : root;
  ///   if (beneath == '.') beneath = '';
  ///   String resolve(String path) {
  ///     return p.joinAll([root, ...p.posix.split(path)]);
  ///   }
  ///
  ///   Ignore.listFiles(
  ///     beneath: beneath,
  ///     listDir: (dir) => Directory(resolve(dir)).listSync().map((x) {
  ///        final relative = p.relative(x.path, from: root);
  ///       return p.posix.joinAll(p.split(relative));
  ///     }),
  ///     ignoreForDir: (dir) {
  ///       final f = File(resolve('dir/.gitignore'));
  ///       return f.existsSync() ? Ignore([f.readAsStringSync()]) : null;
  ///     },
  ///     isDir: (dir) => Directory(resolve(dir)).existsSync(),
  ///   ).forEach(print);
  /// }
  /// ```
  static List<String> listFiles({
    String beneath = '',
    required Iterable<String> Function(String) listDir,
    required Ignore? Function(String) ignoreForDir,
    required bool Function(String) isDir,
    bool includeDirs = false,
  }) {
    if (beneath.startsWith('/') ||
        beneath.startsWith('./') ||
        beneath.startsWith('../')) {
      throw ArgumentError.value(
          'must be relative and normalized', 'beneath', beneath);
    }
    if (beneath.endsWith('/')) {
      throw ArgumentError.value('must not end with /', beneath);
    }
    // To streamline the algorithm we represent all paths as starting with '/'
    // and the empty path as just '/'.
    if (beneath == '.') beneath = '';
    beneath = '/$beneath';

    // Will contain all the files that are not ignored.
    final result = <String>[];
    // At any given point in the search, this will contain the Ignores from
    // directories leading up to the current entity.
    // The single `null` aligns popping and pushing in this stack with [toVisit]
    // below.
    final ignoreStack = <_IgnorePrefixPair?>[null];
    // Find all ignores between './' and [beneath] (not inclusive).

    // [index] points at the next '/' in the path.
    var index = -1;
    while ((index = beneath.indexOf('/', index + 1)) != -1) {
      final partial = beneath.substring(0, index + 1);
      if (_matchesStack(ignoreStack, partial)) {
        // A directory on the way towards [beneath] was ignored. Empty result.
        return <String>[];
      }
      final ignore = ignoreForDir(
          partial == '/' ? '.' : partial.substring(1, partial.length - 1));
      ignoreStack
          .add(ignore == null ? null : _IgnorePrefixPair(ignore, partial));
    }
    // Do a depth first tree-search starting at [beneath].
    // toVisit is a stack containing all items that are waiting to be processed.
    final toVisit = [
      [beneath]
    ];
    while (toVisit.isNotEmpty) {
      final topOfStack = toVisit.last;
      if (topOfStack.isEmpty) {
        toVisit.removeLast();
        ignoreStack.removeLast();
        continue;
      }
      final current = topOfStack.removeLast();
      // This is the version of current we present to the callbacks and in
      // [result].
      //
      // The empty path is represented as '.' and there is no leading '/'.
      final normalizedCurrent = current == '/' ? '.' : current.substring(1);
      final currentIsDir = isDir(normalizedCurrent);
      if (_matchesStack(ignoreStack, currentIsDir ? '$current/' : current)) {
        // current was ignored. Continue with the next item.
        continue;
      }
      if (currentIsDir) {
        final ignore = ignoreForDir(normalizedCurrent);
        ignoreStack.add(ignore == null
            ? null
            : _IgnorePrefixPair(
                ignore, current == '/' ? current : '$current/'));
        // Put all entities in current on the stack to be processed.
        toVisit.add(listDir(normalizedCurrent).map((x) => '/$x').toList());
        if (includeDirs) {
          result.add(normalizedCurrent);
        }
      } else {
        result.add(normalizedCurrent);
      }
    }
    return result;
  }
}

class _IgnoreParseResult {
  // The parsed pattern.
  final String pattern;

  // The resulting matching rule. `null` if the pattern was empty or invalid.
  final _IgnoreRule? rule;

  // An invalid pattern is also considered empty.
  bool get empty => rule == null;

  bool get valid => exception == null;

  // For invalid patterns this contains a description of the problem.
  final FormatException? exception;

  _IgnoreParseResult(this.pattern, this.rule) : exception = null;

  _IgnoreParseResult.invalid(this.pattern, this.exception) : rule = null;

  _IgnoreParseResult.empty(this.pattern)
      : rule = null,
        exception = null;
}

class _IgnoreRule {
  /// A regular expression that represents this rule.
  final RegExp pattern;
  final bool negative;

  /// The String this pattern was generated from.
  final String original;

  _IgnoreRule(this.pattern, this.negative, this.original);

  @override
  String toString() {
    // TODO: implement toString
    return '$original -> $pattern';
  }
}

/// Pattern for a line-break which accepts CR LF and LF.
final _lineBreakPattern = RegExp('\r?\n');

/// [onInvalidPattern] can be used to handle parse failures. If
/// [onInvalidPattern] is `null` invalid patterns are ignored.
Iterable<_IgnoreRule> _parseIgnorePatterns(
  Iterable<String> patterns,
  bool ignoreCase, {
  void Function(String pattern, FormatException exception)? onInvalidPattern,
}) sync* {
  ArgumentError.checkNotNull(patterns, 'patterns');
  ArgumentError.checkNotNull(ignoreCase, 'ignoreCase');
  onInvalidPattern ??= (_, __) {};

  final parsedPatterns = patterns
      .expand((s) => s.split(_lineBreakPattern))
      .map((pattern) => _parseIgnorePattern(pattern, ignoreCase));

  for (final r in parsedPatterns) {
    if (!r.valid) {
      onInvalidPattern(r.pattern, r.exception!);
    }
    if (!r.empty) {
      yield r.rule!;
    }
  }
}

_IgnoreParseResult _parseIgnorePattern(String pattern, bool ignoreCase) {
  // Check if patterns is a comment
  if (pattern.startsWith('#')) {
    return _IgnoreParseResult.empty(pattern);
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
  if (first == end) return _IgnoreParseResult.empty(pattern);

  var current = first;
  String? peekChar() => current >= end ? null : pattern[current];

  var expr = '';

  // Parses the inside of a [] range. Returns the value as a RegExp character
  // range, or null if the pattern was broken.
  String? parseCharacterRange() {
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
      } else if (peekChar() == '/' || peekChar() == null) {
        // /a/* should not match '/a/'
        expr += '[^/]+';
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
        return _IgnoreParseResult.invalid(
          pattern,
          FormatException(
              'Pattern "$pattern" had an invalid `[a-b]` style character range',
              pattern,
              current),
        );
      }
      expr += '[$characterRange]';
    } else if (nextChar == '\\') {
      // Escapes
      final escaped = peekChar();
      if (escaped == null) {
        return _IgnoreParseResult.invalid(
          pattern,
          FormatException(
              'Pattern "$pattern" end of pattern inside character escape.',
              pattern,
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
  }
  try {
    return _IgnoreParseResult(
        pattern,
        _IgnoreRule(
            RegExp(expr, caseSensitive: !ignoreCase), negative, pattern));
  } on FormatException catch (e) {
    throw AssertionError(
        'Created broken expression "$expr" from ignore pattern "$pattern" -> $e');
  }
}

/// A [Ignore] object, paired with the prefix where it is found in the directory
/// hierarchy.
class _IgnorePrefixPair {
  final Ignore ignore;
  final String prefix;

  _IgnorePrefixPair(this.ignore, this.prefix);

  @override
  String toString() {
    return '{${ignore._rules.map((r) => r.original)} $prefix}';
  }
}

/// Returns true if any of [ignores] has a match of [path] that is not negated
/// by a later one.
///
/// expects [path] to start with '/'
///
/// If [path] should be matched as a directory, it should end with '/'.
bool _matchesStack(List<_IgnorePrefixPair?> ignores, String path) {
  // This is optimized by trying the rules in reverse order.
  // If a rule matches, the result is true if the rule is not negative.
  for (final ignorePair in ignores.reversed) {
    if (ignorePair == null) continue;
    final prefixLength = ignorePair.prefix.length;
    final s =
        prefixLength == 0 ? path : path.substring(ignorePair.prefix.length);
    for (final rule in ignorePair.ignore._rules.reversed) {
      if (rule.pattern.hasMatch(s)) {
        return !rule.negative;
      }
    }
  }
  return false;
}
