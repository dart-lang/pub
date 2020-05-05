// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Generic utility functions. Stuff that should possibly be in core.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:stack_trace/stack_trace.dart';

import 'exceptions.dart';
import 'io.dart';
import 'log.dart' as log;

/// Whether Pub is running its own tests under Travis.CI.
final isTravis = Platform.environment['TRAVIS_REPO_SLUG'] == 'dart-lang/pub';

/// A regular expression matching a Dart identifier.
///
/// This also matches a package name, since they must be Dart identifiers.
final identifierRegExp = RegExp(r'[a-zA-Z_]\w*');

/// Like [identifierRegExp], but anchored so that it only matches strings that
/// are *just* Dart identifiers.
final onlyIdentifierRegExp = RegExp('^${identifierRegExp.pattern}\$');

/// Dart reserved words, from the Dart spec.
const reservedWords = [
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with'
];

/// An cryptographically secure instance of [math.Random].
final random = math.Random.secure();

/// The maximum line length for output.
///
/// If pub isn't attached to a terminal, uses an infinite line length and does
/// not wrap text.
final int _lineLength = () {
  try {
    return stdout.terminalColumns;
  } on StdoutException {
    return null;
  }
}();

/// A pair of values.
class Pair<E, F> {
  E first;
  F last;

  Pair(this.first, this.last);

  @override
  String toString() => '($first, $last)';

  @override
  bool operator ==(other) {
    if (other is! Pair) return false;
    return other.first == first && other.last == last;
  }

  @override
  int get hashCode => first.hashCode ^ last.hashCode;
}

/// Runs [callback] in an error zone and pipes any unhandled error to the
/// returned [Future].
///
/// If the returned [Future] produces an error, its stack trace will always be a
/// [Chain]. By default, this chain will contain only the local stack trace, but
/// if [captureStackChains] is passed, it will contain the full stack chain for
/// the error.
Future<T> captureErrors<T>(Future<T> Function() callback,
    {bool captureStackChains = false}) {
  var completer = Completer<T>();
  void wrappedCallback() {
    Future.sync(callback).then(completer.complete).catchError((e, stackTrace) {
      // [stackTrace] can be null if we're running without [captureStackChains],
      // since dart:io will often throw errors without stack traces.
      if (stackTrace != null) {
        stackTrace = Chain.forTrace(stackTrace);
      } else {
        stackTrace = Chain([]);
      }
      if (!completer.isCompleted) completer.completeError(e, stackTrace);
    });
  }

  if (captureStackChains) {
    Chain.capture(wrappedCallback, onError: (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });
  } else {
    runZoned(wrappedCallback, onError: (e, stackTrace) {
      if (stackTrace == null) {
        stackTrace = Chain.current();
      } else {
        stackTrace = Chain([Trace.from(stackTrace)]);
      }
      if (!completer.isCompleted) completer.completeError(e, stackTrace);
    });
  }

  return completer.future;
}

/// Like [Future.wait], but prints all errors from the futures as they occur and
/// only returns once all Futures have completed, successfully or not.
///
/// This will wrap the first error thrown in a [SilentException] and rethrow it.
Future<List<T>> waitAndPrintErrors<T>(Iterable<Future<T>> futures) {
  return Future.wait(futures.map((future) {
    return future.catchError((error, stackTrace) {
      log.exception(error, stackTrace);
      throw error;
    });
  })).catchError((error, stackTrace) {
    throw SilentException(error, stackTrace);
  });
}

/// Returns a [StreamTransformer] that will call [onDone] when the stream
/// completes.
///
/// The stream will be passed through unchanged.
StreamTransformer<T, T> onDoneTransformer<T>(void Function() onDone) {
  return StreamTransformer<T, T>.fromHandlers(handleDone: (sink) {
    onDone();
    sink.close();
  });
}

/// Pads [source] to [length] by adding [char]s at the beginning.
///
/// If [char] is `null`, it defaults to a space.
String _padLeft(String source, int length, [String char]) {
  char ??= ' ';
  if (source.length >= length) return source;

  return char * (length - source.length) + source;
}

/// Returns a labelled sentence fragment starting with [name] listing the
/// elements [iter].
///
/// If [iter] does not have one item, name will be pluralized by adding "s" or
/// using [plural], if given.
String namedSequence(String name, Iterable iter, [String plural]) {
  if (iter.length == 1) return '$name ${iter.single}';

  plural ??= '${name}s';
  return '$plural ${toSentence(iter)}';
}

/// Returns a sentence fragment listing the elements of [iter].
///
/// This converts each element of [iter] to a string and separates them with
/// commas and/or [conjunction] (`"and"` by default) where appropriate.
String toSentence(Iterable iter, {String conjunction}) {
  if (iter.length == 1) return iter.first.toString();
  conjunction ??= 'and';
  return iter.take(iter.length - 1).join(', ') + ' $conjunction ${iter.last}';
}

/// Returns [name] if [number] is 1, or the plural of [name] otherwise.
///
/// By default, this just adds "s" to the end of [name] to get the plural. If
/// [plural] is passed, that's used instead.
String pluralize(String name, int number, {String plural}) {
  if (number == 1) return name;
  if (plural != null) return plural;
  return '${name}s';
}

/// Returns [text] with the first letter capitalized.
String capitalize(String text) =>
    text.substring(0, 1).toUpperCase() + text.substring(1);

/// Returns whether [host] is a host for a localhost or loopback URL.
///
/// Unlike [InternetAddress.isLoopback], this hostnames from URLs as well as
/// from [InternetAddress]es, including "localhost".
bool isLoopback(String host) {
  if (host == 'localhost') return true;

  // IPv6 hosts in URLs are surrounded by square brackets.
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }

  try {
    return InternetAddress(host).isLoopback;
  } on ArgumentError catch (_) // ignore: avoid_catching_errors
  {
    // The host isn't an IP address and isn't "localhost', so it's almost
    // certainly not a loopback host.
    return false;
  }
}

/// Randomly chooses a single element in [elements].
T choose<T>(List<T> elements) => elements[random.nextInt(elements.length)];

/// Returns a list containing the sorted elements of [iter].
List<T> ordered<T extends Comparable<T>>(Iterable<T> iter) {
  var list = iter.toList();
  list.sort();
  return list;
}

/// Given a list of filenames, returns a set of patterns that can be used to
/// filter for those filenames.
///
/// For a given path, that path ends with some string in the returned set if
/// and only if that path's basename is in [files].
Set<String> createFileFilter(Iterable<String> files) {
  return files.expand<String>((file) {
    var result = ['/$file'];
    if (Platform.isWindows) result.add('\\$file');
    return result;
  }).toSet();
}

/// Given a blacklist of directory names, returns a set of patterns that can
/// be used to filter for those directory names.
///
/// For a given path, that path contains some string in the returned set if
/// and only if one of that path's components is in [dirs].
Set<String> createDirectoryFilter(Iterable<String> dirs) {
  return dirs.expand<String>((dir) {
    var result = ['/$dir/'];
    if (Platform.isWindows) {
      result..add('/$dir\\')..add('\\$dir/')..add('\\$dir\\');
    }
    return result;
  }).toSet();
}

/// Returns the maximum value in [iter] by [compare].
///
/// [compare] defaults to [Comparable.compare].
T maxAll<T extends Comparable>(Iterable<T> iter, [int Function(T, T) compare]) {
  compare ??= Comparable.compare;
  return iter
      .reduce((max, element) => compare(element, max) > 0 ? element : max);
}

/// Returns the element of [values] for which [orderBy] returns the smallest
/// value.
///
/// Returns the first such value in case of ties.
///
/// Starts all the [orderBy] invocations in parallel.
Future<S> minByAsync<S, T>(
    Iterable<S> values, Future<T> Function(S) orderBy) async {
  int minIndex;
  T minOrderBy;
  List valuesList = values.toList();
  final orderByResults = await Future.wait(values.map(orderBy));
  for (var i = 0; i < orderByResults.length; i++) {
    final elementOrderBy = orderByResults[i];
    if (minOrderBy == null ||
        (elementOrderBy as Comparable).compareTo(minOrderBy) < 0) {
      minIndex = i;
      minOrderBy = elementOrderBy;
    }
  }
  return valuesList[minIndex];
}

/// Like [List.sublist], but for any iterable.
Iterable<T> slice<T>(Iterable<T> values, int start, int end) {
  if (end <= start) {
    throw RangeError.range(
        end, start + 1, null, 'end', 'must be greater than start');
  }
  return values.skip(start).take(end - start);
}

/// Like [Iterable.fold], but for an asynchronous [combine] function.
Future<S> foldAsync<S, T>(Iterable<T> values, S initialValue,
        Future<S> Function(S previous, T element) combine) =>
    values.fold(
        Future.value(initialValue),
        (previousFuture, element) =>
            previousFuture.then((previous) => combine(previous, element)));

/// Replace each instance of [matcher] in [source] with the return value of
/// [fn].
String replace(String source, Pattern matcher, String Function(Match) fn) {
  var buffer = StringBuffer();
  var start = 0;
  for (var match in matcher.allMatches(source)) {
    buffer.write(source.substring(start, match.start));
    start = match.end;
    buffer.write(fn(match));
  }
  buffer.write(source.substring(start));
  return buffer.toString();
}

/// Returns the hex-encoded sha1 hash of [source].
String sha1(String source) =>
    crypto.sha1.convert(utf8.encode(source)).toString();

/// A regular expression matching a trailing CR character.
final _trailingCR = RegExp(r'\r$');

// TODO(nweiz): Use `text.split(new RegExp("\r\n?|\n\r?"))` when issue 9360 is
// fixed.
/// Splits [text] on its line breaks in a Windows-line-break-friendly way.
List<String> splitLines(String text) =>
    text.split('\n').map((line) => line.replaceFirst(_trailingCR, '')).toList();

/// Like [String.split], but only splits on the first occurrence of the pattern.
///
/// This always returns an array of two elements or fewer.
List<String> split1(String toSplit, String pattern) {
  if (toSplit.isEmpty) return <String>[];

  var index = toSplit.indexOf(pattern);
  if (index == -1) return [toSplit];
  return [
    toSplit.substring(0, index),
    toSplit.substring(index + pattern.length)
  ];
}

/// Convert a URL query string (or `application/x-www-form-urlencoded` body)
/// into a [Map] from parameter names to values.
Map<String, String> queryToMap(String queryList) {
  var map = <String, String>{};
  for (var pair in queryList.split('&')) {
    var split = split1(pair, '=');
    if (split.isEmpty) continue;
    var key = _urlDecode(split[0]);
    var value = split.length > 1 ? _urlDecode(split[1]) : '';
    map[key] = value;
  }
  return map;
}

/// Returns a human-friendly representation of [duration].
String niceDuration(Duration duration) {
  var hasMinutes = duration.inMinutes > 0;
  var result = hasMinutes ? '${duration.inMinutes}:' : '';

  var s = duration.inSeconds % 60;
  var ms = duration.inMilliseconds % 1000;

  // If we're using verbose logging, be more verbose but more accurate when
  // reporting timing information.
  var msString = log.verbosity.isLevelVisible(log.Level.FINE)
      ? _padLeft(ms.toString(), 3, '0')
      : (ms ~/ 100).toString();

  return "$result${hasMinutes ? _padLeft(s.toString(), 2, '0') : s}"
      '.${msString}s';
}

/// Decodes a URL-encoded string.
///
/// Unlike [Uri.decodeComponent], this includes replacing `+` with ` `.
String _urlDecode(String encoded) =>
    Uri.decodeComponent(encoded.replaceAll('+', ' '));

/// Set to `true` if ANSI colors should be output regardless of terminalD
bool forceColors = false;

/// Whether "special" strings such as Unicode characters or color escapes are
/// safe to use.
///
/// On Windows or when not printing to a terminal, only printable ASCII
/// characters should be used.
bool get canUseSpecialChars =>
    forceColors ||
    (!runningFromTest &&
        !runningAsTest &&
        stdioType(stdout) == StdioType.terminal &&
        stdout.supportsAnsiEscapes);

/// Gets a "special" string (ANSI escape or Unicode).
///
/// On Windows or when not printing to a terminal, returns something else since
/// those aren't supported.
String getSpecial(String special, [String onWindows = '']) =>
    canUseSpecialChars ? special : onWindows;

/// Prepends each line in [text] with [prefix].
///
/// If [firstPrefix] is passed, the first line is prefixed with that instead.
String prefixLines(String text, {String prefix = '| ', String firstPrefix}) {
  var lines = text.split('\n');
  if (firstPrefix == null) {
    return lines.map((line) => '$prefix$line').join('\n');
  }

  var firstLine = '$firstPrefix${lines.first}';
  lines = lines.skip(1).map((line) => '$prefix$line').toList();
  lines.insert(0, firstLine);
  return lines.join('\n');
}

/// Whether today is April Fools' day.
bool get isAprilFools {
  // Tests should never see April Fools' output.
  if (runningFromTest) return false;

  var date = DateTime.now();
  return date.month == 4 && date.day == 1;
}

/// The subset of strings that don't need quoting in YAML.
///
/// This pattern does not strictly follow the plain scalar grammar of YAML,
/// which means some strings may be unnecessarily quoted, but it's much simpler.
final _unquotableYamlString = RegExp(r'^[a-zA-Z_-][a-zA-Z_0-9-]*$');

/// Converts [data], which is a parsed YAML object, to a pretty-printed string,
/// using indentation for maps.
String yamlToString(data) {
  var buffer = StringBuffer();

  void _stringify(bool isMapValue, String indent, data) {
    // TODO(nweiz): Serialize using the YAML library once it supports
    // serialization.

    // Use indentation for (non-empty) maps.
    if (data is Map && data.isNotEmpty) {
      if (isMapValue) {
        buffer.writeln();
        indent += '  ';
      }

      // Sort the keys. This minimizes deltas in diffs.
      var keys = data.keys.toList();
      keys.sort((a, b) => a.toString().compareTo(b.toString()));

      var first = true;
      for (var key in keys) {
        if (!first) buffer.writeln();
        first = false;

        var keyString = key;
        if (key is! String || !_unquotableYamlString.hasMatch(key)) {
          keyString = jsonEncode(key);
        }

        buffer.write('$indent$keyString:');
        _stringify(true, indent, data[key]);
      }

      return;
    }

    // Everything else we just stringify using JSON to handle escapes in
    // strings and number formatting.
    var string = data;

    // Don't quote plain strings if not needed.
    if (data is! String || !_unquotableYamlString.hasMatch(data)) {
      string = jsonEncode(data);
    }

    if (isMapValue) {
      buffer.write(' $string');
    } else {
      buffer.write('$indent$string');
    }
  }

  _stringify(false, '', data);
  return buffer.toString();
}

/// Throw a [ApplicationException] with [message].
@alwaysThrows
void fail(String message, [innerError, StackTrace innerTrace]) {
  if (innerError != null) {
    throw WrappedException(message, innerError, innerTrace);
  } else {
    throw ApplicationException(message);
  }
}

/// Throw a [DataException] with [message] to indicate that the command has
/// failed because of invalid input data.
///
/// This will report the error and cause pub to exit with [exit_codes.DATA].
void dataError(String message) => throw DataException(message);

/// Returns a UUID in v4 format as a `String`.
///
/// If [bytes] is provided, it must be length 16 and have values between `0` and
/// `255` inclusive.
///
/// If [bytes] is not provided, it is generated using `Random.secure`.
String createUuid([List<int> bytes]) {
  var rnd = math.Random.secure();

  // See http://www.cryptosys.net/pki/uuid-rfc4122.html for notes
  bytes ??= List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  var chars = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-'
      '${chars.substring(12, 16)}-${chars.substring(16, 20)}-${chars.substring(20, 32)}';
}

/// Wraps [text] so that it fits within [_lineLength], if there is a line length.
///
/// This preserves existing newlines and doesn't consider terminal color escapes
/// part of a word's length. It only splits words on spaces, not on other sorts
/// of whitespace.
///
/// If [prefix] is passed, it's added at the beginning of any wrapped lines.
String wordWrap(String text, {String prefix}) {
  // If there is no limit, don't wrap.
  if (_lineLength == null) return text;

  prefix ??= '';
  return text.split('\n').map((originalLine) {
    var buffer = StringBuffer();
    var lengthSoFar = 0;
    var firstLine = true;
    for (var word in originalLine.split(' ')) {
      var wordLength = _withoutColors(word).length;
      if (wordLength > _lineLength) {
        if (lengthSoFar != 0) buffer.writeln();
        if (!firstLine) buffer.write(prefix);
        buffer.writeln(word);
        firstLine = false;
      } else if (lengthSoFar == 0) {
        if (!firstLine) buffer.write(prefix);
        buffer.write(word);
        lengthSoFar = wordLength + prefix.length;
      } else if (lengthSoFar + 1 + wordLength > _lineLength) {
        buffer.writeln();
        buffer.write(prefix);
        buffer.write(word);
        lengthSoFar = wordLength + prefix.length;
        firstLine = false;
      } else {
        buffer.write(' $word');
        lengthSoFar += 1 + wordLength;
      }
    }
    return buffer.toString();
  }).join('\n');
}

/// A regular expression matching terminal color codes.
final _colorCode = RegExp('\u001b\\[[0-9;]+m');

/// Returns [str] without any color codes.
String _withoutColors(String str) => str.replaceAll(_colorCode, '');

/// A regular expression to match the exception prefix that some exceptions'
/// [Object.toString] values contain.
final _exceptionPrefix = RegExp(r'^([A-Z][a-zA-Z]*)?(Exception|Error): ');

/// Get a string description of an exception.
///
/// Many exceptions include the exception class name at the beginning of their
/// [toString], so we remove that if it exists.
String getErrorMessage(error) =>
    error.toString().replaceFirst(_exceptionPrefix, '');

/// Returns whether [version1] and [version2] are the same, ignoring the
/// pre-release modifiers on each if they exist.
bool equalsIgnoringPreRelease(Version version1, Version version2) =>
    version1.major == version2.major &&
    version1.minor == version2.minor &&
    version1.patch == version2.patch;
