// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';

import '../exceptions.dart';
import '../log.dart' as log;
import '../package_name.dart';
import '../sdk.dart';
import '../utils.dart';
import 'incompatibility.dart';
import 'incompatibility_cause.dart';

/// An exception indicating that version solving failed.
class SolveFailure implements ApplicationException {
  /// The root incompatibility.
  ///
  /// This will always indicate that the root package is unselectable. That is,
  /// it will have one term, which will be the root package.
  final Incompatibility incompatibility;

  @override
  String get message => toString();

  /// Returns a [PackageNotFoundException] that (transitively) caused this
  /// failure, or `null` if it wasn't caused by a [PackageNotFoundException].
  ///
  /// If multiple [PackageNotFoundException]s caused the error, it's undefined
  /// which one is returned.
  PackageNotFoundException get packageNotFound {
    for (var incompatibility in incompatibility.externalIncompatibilities) {
      var cause = incompatibility.cause;
      if (cause is PackageNotFoundCause) return cause.exception;
    }
    return null;
  }

  SolveFailure(this.incompatibility)
      : assert(incompatibility.terms.single.package.isRoot);

  /// Describes how [incompatibility] was derived, and thus why version solving
  /// failed.
  @override
  String toString() => _Writer(incompatibility).write();
}

/// A class that writes a human-readable description of the cause of a
/// [SolveFailure].
///
/// See https://github.com/dart-lang/pub/tree/master/doc/solver.md#error-reporting
/// for details on how this algorithm works.
class _Writer {
  /// The root incompatibility.
  final Incompatibility _root;

  /// The number of times each [Incompatibility] appears in [_root]'s derivation
  /// tree.
  ///
  /// When an [Incompatibility] is used in multiple derivations, we need to give
  /// it a number so we can refer back to it later on.
  final _derivations = <Incompatibility, int>{};

  /// The lines in the proof.
  ///
  /// Each line is a message/number pair. The message describes a single
  /// incompatibility, and why its terms are incompatible. The number is
  /// optional and indicates the explicit number that should be associated with
  /// the line so it can be referred to later on.
  final _lines = <Pair<String, int>>[];

  // A map from incompatibilities to the line numbers that were written for
  // those incompatibilities.
  final _lineNumbers = <Incompatibility, int>{};

  _Writer(this._root) {
    _countDerivations(_root);
  }

  /// Populates [_derivations] for [incompatibility] and its transitive causes.
  void _countDerivations(Incompatibility incompatibility) {
    if (_derivations.containsKey(incompatibility)) {
      _derivations[incompatibility]++;
    } else {
      _derivations[incompatibility] = 1;
      var cause = incompatibility.cause;
      if (cause is ConflictCause) {
        _countDerivations(cause.conflict);
        _countDerivations(cause.other);
      }
    }
  }

  String write() {
    var buffer = StringBuffer();

    // SDKs whose version constraints weren't matched.
    var sdkConstraintCauses = <Sdk>{};

    // SDKs implicated in any way in the solve failure.
    var sdkCauses = <Sdk>{};

    for (var incompatibility in _root.externalIncompatibilities) {
      var cause = incompatibility.cause;
      if (cause is PackageNotFoundCause && cause.sdk != null) {
        sdkCauses.add(cause.sdk);
      } else if (cause is SdkCause) {
        sdkCauses.add(cause.sdk);
        sdkConstraintCauses.add(cause.sdk);
      }
    }

    // If the failure was caused in part by unsatisfied SDK constraints,
    // indicate the actual versions so we don't have to list them (possibly
    // multiple times) in the main body of the error message.
    //
    // Iterate through [sdks] to ensure that SDKs versions are printed in a
    // consistent order
    var wroteLine = false;
    for (var sdk in sdks.values) {
      if (!sdkConstraintCauses.contains(sdk)) continue;
      if (!sdk.isAvailable) continue;
      wroteLine = true;
      buffer.writeln('The current ${sdk.name} SDK version is ${sdk.version}.');
    }
    if (wroteLine) buffer.writeln();

    if (_root.cause is ConflictCause) {
      _visit(_root, const {});
    } else {
      _write(_root, 'Because $_root, version solving failed.');
    }

    // Only add line numbers if the derivation actually needs to refer to a line
    // by number.
    var padding =
        _lineNumbers.isEmpty ? 0 : '(${_lineNumbers.values.last}) '.length;

    var lastWasEmpty = false;
    for (var line in _lines) {
      var message = line.first;
      if (message.isEmpty) {
        if (!lastWasEmpty) buffer.writeln();
        lastWasEmpty = true;
        continue;
      } else {
        lastWasEmpty = false;
      }

      var number = line.last;
      if (number != null) {
        message = '($number)'.padRight(padding) + message;
      } else {
        message = ' ' * padding + message;
      }

      buffer.writeln(wordWrap(message, prefix: ' ' * (padding + 2)));
    }

    // Iterate through [sdks] to ensure that SDKs versions are printed in a
    // consistent order
    for (var sdk in sdks.values) {
      if (!sdkCauses.contains(sdk)) continue;
      if (sdk.isAvailable) continue;
      if (sdk.installMessage == null) continue;
      buffer.writeln();
      buffer.writeln(sdk.installMessage);
    }

    return buffer.toString();
  }

  /// Writes [message] to [_lines].
  ///
  /// The [message] should describe [incompatibility] and how it was derived (if
  /// applicable). If [numbered] is true, this will associate a line number with
  /// [incompatibility] and [message] so that the message can be easily referred
  /// to later.
  void _write(Incompatibility incompatibility, String message,
      {bool numbered = false}) {
    if (numbered) {
      var number = _lineNumbers.length + 1;
      _lineNumbers[incompatibility] = number;
      _lines.add(Pair(message, number));
    } else {
      _lines.add(Pair(message, null));
    }
  }

  /// Writes a proof of [incompatibility] to [_lines].
  ///
  /// If [conclusion] is `true`, [incompatibility] represents the last of a
  /// linear series of derivations. It should be phrased accordingly and given a
  /// line number.
  ///
  /// The [detailsForIncompatibility] controls the amount of detail that should
  /// be written for each package when converting [incompatibility] to a string.
  void _visit(Incompatibility incompatibility,
      Map<String, PackageDetail> detailsForIncompatibility,
      {bool conclusion = false}) {
    // Add explicit numbers for incompatibilities that are written far away
    // from their successors or that are used for multiple derivations.
    var numbered = conclusion || _derivations[incompatibility] > 1;
    var conjunction = conclusion || incompatibility == _root ? 'So,' : 'And';
    var incompatibilityString =
        log.bold(incompatibility.toString(detailsForIncompatibility));

    var cause = incompatibility.cause as ConflictCause;
    var detailsForCause = _detailsForCause(cause);
    if (cause.conflict.cause is ConflictCause &&
        cause.other.cause is ConflictCause) {
      var conflictLine = _lineNumbers[cause.conflict];
      var otherLine = _lineNumbers[cause.other];
      if (conflictLine != null && otherLine != null) {
        _write(
            incompatibility,
            'Because ' +
                cause.conflict.andToString(
                    cause.other, detailsForCause, conflictLine, otherLine) +
                ', $incompatibilityString.',
            numbered: numbered);
      } else if (conflictLine != null || otherLine != null) {
        Incompatibility withLine;
        Incompatibility withoutLine;
        int line;
        if (conflictLine != null) {
          withLine = cause.conflict;
          withoutLine = cause.other;
          line = conflictLine;
        } else {
          withLine = cause.other;
          withoutLine = cause.conflict;
          line = otherLine;
        }

        _visit(withoutLine, detailsForCause);
        _write(
            incompatibility,
            '$conjunction because ${withLine.toString(detailsForCause)} '
            '($line), $incompatibilityString.',
            numbered: numbered);
      } else {
        var singleLineConflict = _isSingleLine(cause.conflict.cause);
        var singleLineOther = _isSingleLine(cause.other.cause);
        if (singleLineOther || singleLineConflict) {
          var first = singleLineOther ? cause.conflict : cause.other;
          var second = singleLineOther ? cause.other : cause.conflict;
          _visit(first, detailsForCause);
          _visit(second, detailsForCause);
          _write(incompatibility, 'Thus, $incompatibilityString.',
              numbered: numbered);
        } else {
          _visit(cause.conflict, {}, conclusion: true);
          _lines.add(Pair('', null));

          _visit(cause.other, detailsForCause);
          _write(
              incompatibility,
              '$conjunction because '
              '${cause.conflict.toString(detailsForCause)} '
              '(${_lineNumbers[cause.conflict]}), '
              '$incompatibilityString.',
              numbered: numbered);
        }
      }
    } else if (cause.conflict.cause is ConflictCause ||
        cause.other.cause is ConflictCause) {
      var derived =
          cause.conflict.cause is ConflictCause ? cause.conflict : cause.other;
      var ext =
          cause.conflict.cause is ConflictCause ? cause.other : cause.conflict;

      var derivedLine = _lineNumbers[derived];
      if (derivedLine != null) {
        _write(
            incompatibility,
            'Because ' +
                ext.andToString(derived, detailsForCause, null, derivedLine) +
                ', $incompatibilityString.',
            numbered: numbered);
      } else if (_isCollapsible(derived)) {
        var derivedCause = derived.cause as ConflictCause;
        var collapsedDerived = derivedCause.conflict.cause is ConflictCause
            ? derivedCause.conflict
            : derivedCause.other;
        var collapsedExt = derivedCause.conflict.cause is ConflictCause
            ? derivedCause.other
            : derivedCause.conflict;

        detailsForCause = mergeMaps(
            detailsForCause, _detailsForCause(derivedCause),
            value: (detail1, detail2) => detail1.max(detail2));

        _visit(collapsedDerived, detailsForCause);
        _write(
            incompatibility,
            '$conjunction because '
            '${collapsedExt.andToString(ext, detailsForCause)}, '
            '$incompatibilityString.',
            numbered: numbered);
      } else {
        _visit(derived, detailsForCause);
        _write(
            incompatibility,
            '$conjunction because ${ext.toString(detailsForCause)}, '
            '$incompatibilityString.',
            numbered: numbered);
      }
    } else {
      _write(
          incompatibility,
          'Because '
          '${cause.conflict.andToString(cause.other, detailsForCause)}, '
          '$incompatibilityString.',
          numbered: numbered);
    }
  }

  /// Returns whether we can collapse the derivation of [incompatibility].
  ///
  /// If [incompatibility] is only used to derive one other incompatibility,
  /// it may make sense to skip that derivation and just derive the second
  /// incompatibility directly from three causes. This is usually clear enough
  /// to the user, and makes the proof much terser.
  ///
  /// For example, instead of writing
  ///
  ///     ... foo ^1.0.0 requires bar ^1.0.0.
  ///     And, because bar ^1.0.0 depends on baz ^1.0.0, foo ^1.0.0 requires
  ///       baz ^1.0.0.
  ///     And, because baz ^1.0.0 depends on qux ^1.0.0, foo ^1.0.0 requires
  ///       qux ^1.0.0.
  ///     ...
  ///
  /// we collapse the two derivations into a single line and write
  ///
  ///     ... foo ^1.0.0 requires bar ^1.0.0.
  ///     And, because bar ^1.0.0 depends on baz ^1.0.0 which depends on
  ///       qux ^1.0.0, foo ^1.0.0 requires qux ^1.0.0.
  ///     ...
  ///
  /// If this returns `true`, [incompatibility] has one external predecessor
  /// and one derived predecessor.
  bool _isCollapsible(Incompatibility incompatibility) {
    // If [incompatibility] is used for multiple derivations, it will need a
    // line number and so will need to be written explicitly.
    if (_derivations[incompatibility] > 1) return false;

    var cause = incompatibility.cause as ConflictCause;
    // If [incompatibility] is derived from two derived incompatibilities,
    // there are too many transitive causes to display concisely.
    if (cause.conflict.cause is ConflictCause &&
        cause.other.cause is ConflictCause) {
      return false;
    }

    // If [incompatibility] is derived from two external incompatibilities, it
    // tends to be confusing to collapse it.
    if (cause.conflict.cause is! ConflictCause &&
        cause.other.cause is! ConflictCause) {
      return false;
    }

    // If [incompatibility]'s internal cause is numbered, collapsing it would
    // get too noisy.
    var complex =
        cause.conflict.cause is ConflictCause ? cause.conflict : cause.other;
    return !_lineNumbers.containsKey(complex);
  }

  // Returns whether or not [cause]'s incompatibility can be represented in a
  // single line without requiring a multi-line derivation.
  bool _isSingleLine(ConflictCause cause) =>
      cause.conflict.cause is! ConflictCause &&
      cause.other.cause is! ConflictCause;

  /// Returns the amount of detail needed for each package to accurately
  /// describe [cause].
  ///
  /// If the same package name appears in both of [cause]'s incompatibilities
  /// but each has a different source, those incompatibilities should explicitly
  /// print their sources, and similarly for differing descriptions.
  Map<String, PackageDetail> _detailsForCause(ConflictCause cause) {
    var conflictPackages = <String, PackageName>{};
    for (var term in cause.conflict.terms) {
      if (term.package.isRoot) continue;
      conflictPackages[term.package.name] = term.package;
    }

    var details = <String, PackageDetail>{};
    for (var term in cause.other.terms) {
      var conflictPackage = conflictPackages[term.package.name];
      if (term.package.isRoot) continue;
      if (conflictPackage == null) continue;
      if (conflictPackage.source != term.package.source) {
        details[term.package.name] =
            const PackageDetail(showSource: true, showVersion: false);
      } else if (!conflictPackage.samePackage(term.package)) {
        details[term.package.name] =
            const PackageDetail(showDescription: true, showVersion: false);
      }
    }

    return details;
  }
}
