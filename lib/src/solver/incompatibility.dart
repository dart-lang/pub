// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../package_name.dart';
import 'incompatibility_cause.dart';
import 'term.dart';

/// A set of mutually-incompatible terms.
///
/// See https://github.com/dart-lang/pub/tree/master/doc/solver.md#incompatibility.
class Incompatibility {
  /// The mutually-incompatible terms.
  final List<Term> terms;

  /// The reason [terms] are incompatible.
  final IncompatibilityCause cause;

  /// Whether this incompatibility indicates that version solving as a whole has
  /// failed.
  bool get isFailure =>
      terms.isEmpty || (terms.length == 1 && terms.first.package.isRoot);

  /// Returns all external incompatibilities in this incompatibility's
  /// derivation graph.
  Iterable<Incompatibility> get externalIncompatibilities sync* {
    if (cause is ConflictCause) {
      final cause = this.cause as ConflictCause;
      yield* cause.conflict.externalIncompatibilities;
      yield* cause.other.externalIncompatibilities;
    } else {
      yield this;
    }
  }

  /// Creates an incompatibility with [terms].
  ///
  /// This normalizes [terms] so that each package has at most one term
  /// referring to it.
  factory Incompatibility(List<Term> terms, IncompatibilityCause cause) {
    // Remove the root package from generated incompatibilities, since it will
    // always be satisfied. This makes error reporting clearer, and may also
    // make solving more efficient.
    if (terms.length != 1 &&
        cause is ConflictCause &&
        terms.any((term) => term.isPositive && term.package.isRoot)) {
      terms = terms
          .where((term) => !term.isPositive || !term.package.isRoot)
          .toList();
    }

    if (terms.length == 1 ||
        // Short-circuit in the common case of a two-term incompatibility with
        // two different packages (for example, a dependency).
        (terms.length == 2 &&
            terms.first.package.name != terms.last.package.name)) {
      return Incompatibility._(terms, cause);
    }

    // Coalesce multiple terms about the same package if possible.
    final byName = <String, Map<PackageRef, Term>>{};
    for (var term in terms) {
      final byRef = byName.putIfAbsent(term.package.name, () => {});
      final ref = term.package.toRef();
      if (byRef.containsKey(ref)) {
        // If we have two terms that refer to the same package but have a null
        // intersection, they're mutually exclusive, making this incompatibility
        // irrelevant, since we already know that mutually exclusive version
        // ranges are incompatible. We should never derive an irrelevant
        // incompatibility.
        byRef[ref] = byRef[ref]!.intersect(term)!;
      } else {
        byRef[ref] = term;
      }
    }

    return Incompatibility._(
      byName.values.expand((byRef) {
        // If there are any positive terms for a given package, we can discard
        // any negative terms.
        final positiveTerms =
            byRef.values.where((term) => term.isPositive).toList();
        if (positiveTerms.isNotEmpty) return positiveTerms;

        return byRef.values;
      }).toList(),
      cause,
    );
  }

  Incompatibility._(this.terms, this.cause);

  /// Returns a string representation of [this].
  ///
  /// If [details] is passed, it controls the amount of detail that's written
  /// for packages with the given names.
  @override
  String toString([Map<String, PackageDetail>? details]) {
    if (cause is DependencyIncompatibilityCause) {
      assert(terms.length == 2);

      final depender = terms.first;
      final dependee = terms.last;
      assert(depender.isPositive);
      assert(!dependee.isPositive);

      return '${_terse(depender, details, allowEvery: true)} depends on '
          '${_terse(dependee, details)}';
    } else if (cause is SdkIncompatibilityCause) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);

      final cause = this.cause as SdkIncompatibilityCause;
      final buffer =
          StringBuffer(_terse(terms.first, details, allowEvery: true));
      if (cause.noNullSafetyCause) {
        buffer.write(' doesn\'t support null safety');
      } else {
        buffer.write(' requires ');
        if (!cause.sdk.isAvailable) {
          buffer.write('the ${cause.sdk.name} SDK');
        } else {
          if (cause.sdk.name != 'Dart') buffer.write('${cause.sdk.name} ');
          buffer.write('SDK version ${cause.constraint}');
        }
      }
      return buffer.toString();
    } else if (cause is NoVersionsIncompatibilityCause) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);
      return 'no versions of ${_terseRef(terms.first, details)} '
          'match ${terms.first.constraint}';
    } else if (cause is PackageNotFoundIncompatibilityCause) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);

      final cause = this.cause as PackageNotFoundIncompatibilityCause;
      return "${_terseRef(terms.first, details)} doesn't exist "
          '(${cause.exception.message})';
    } else if (cause is UnknownSourceIncompatibilityCause) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);
      return '${terms.first.package.name} comes from unknown source '
          '"${terms.first.package.source}"';
    } else if (cause is RootIncompatibilityCause) {
      // [RootIncompatibilityCause] is only used when a package depends on the
      // entrypoint with an incompatible version, so we want to print the
      // entrypoint's actual version to make it clear why this failed.
      assert(terms.length == 1);
      assert(!terms.first.isPositive);
      assert(terms.first.package.isRoot);
      return '${terms.first.package.name} is ${terms.first.constraint}';
    } else if (isFailure) {
      return 'version solving failed';
    }

    if (terms.length == 1) {
      final term = terms.single;
      if (term.constraint.isAny) {
        return '${_terseRef(term, details)} is '
            "${term.isPositive ? 'forbidden' : 'required'}";
      } else {
        return '${_terse(term, details)} is '
            "${term.isPositive ? 'forbidden' : 'required'}";
      }
    }

    if (terms.length == 2) {
      final term1 = terms.first;
      final term2 = terms.last;
      if (term1.isPositive == term2.isPositive) {
        if (term1.isPositive) {
          final package1 = term1.constraint.isAny
              ? _terseRef(term1, details)
              : _terse(term1, details);
          final package2 = term2.constraint.isAny
              ? _terseRef(term2, details)
              : _terse(term2, details);
          return '$package1 is incompatible with $package2';
        } else {
          return 'either ${_terse(term1, details)} or '
              '${_terse(term2, details)}';
        }
      }
    }

    final positive = <String>[];
    final negative = <String>[];
    for (var term in terms) {
      (term.isPositive ? positive : negative).add(_terse(term, details));
    }

    if (positive.isNotEmpty && negative.isNotEmpty) {
      if (positive.length == 1) {
        final positiveTerm = terms.firstWhere((term) => term.isPositive);
        return '${_terse(positiveTerm, details, allowEvery: true)} requires '
            "${negative.join(' or ')}";
      } else {
        return "if ${positive.join(' and ')} then ${negative.join(' or ')}";
      }
    } else if (positive.isNotEmpty) {
      return "one of ${positive.join(' or ')} must be false";
    } else {
      return "one of ${negative.join(' or ')} must be true";
    }
  }

  /// Returns the equivalent of `"$this and $other"`, with more intelligent
  /// phrasing for specific patterns.
  ///
  /// If [details] is passed, it controls the amount of detail that's written
  /// for packages with the given names.
  ///
  /// If [thisLine] and/or [otherLine] are passed, they indicate line numbers
  /// that should be associated with [this] and [other], respectively.
  String andToString(
    Incompatibility other, [
    Map<String, PackageDetail>? details,
    int? thisLine,
    int? otherLine,
  ]) {
    final requiresBoth = _tryRequiresBoth(other, details, thisLine, otherLine);
    if (requiresBoth != null) return requiresBoth;

    final requiresThrough =
        _tryRequiresThrough(other, details, thisLine, otherLine);
    if (requiresThrough != null) return requiresThrough;

    final requiresForbidden =
        _tryRequiresForbidden(other, details, thisLine, otherLine);
    if (requiresForbidden != null) return requiresForbidden;

    final buffer = StringBuffer(toString(details));
    if (thisLine != null) buffer.write(' $thisLine');
    buffer.write(' and ${other.toString(details)}');
    if (otherLine != null) buffer.write(' $thisLine');
    return buffer.toString();
  }

  /// If "[this] and [other]" can be expressed as "some package requires both X
  /// and Y", this returns that expression.
  ///
  /// Otherwise, this returns `null`.
  String? _tryRequiresBoth(
    Incompatibility other, [
    Map<String, PackageDetail>? details,
    int? thisLine,
    int? otherLine,
  ]) {
    if (terms.length == 1 || other.terms.length == 1) return null;

    final thisPositive = _singleTermWhere((term) => term.isPositive);
    if (thisPositive == null) return null;
    final otherPositive = other._singleTermWhere((term) => term.isPositive);
    if (otherPositive == null) return null;
    if (thisPositive.package != otherPositive.package) return null;

    final thisNegatives = terms
        .where((term) => !term.isPositive)
        .map((term) => _terse(term, details))
        .join(' or ');
    final otherNegatives = other.terms
        .where((term) => !term.isPositive)
        .map((term) => _terse(term, details))
        .join(' or ');

    final buffer =
        StringBuffer('${_terse(thisPositive, details, allowEvery: true)} ');
    final isDependency = cause is DependencyIncompatibilityCause &&
        other.cause is DependencyIncompatibilityCause;
    buffer.write(isDependency ? 'depends on' : 'requires');
    buffer.write(' both $thisNegatives');
    if (thisLine != null) buffer.write(' ($thisLine)');
    buffer.write(' and $otherNegatives');
    if (otherLine != null) buffer.write(' ($otherLine)');
    return buffer.toString();
  }

  /// If "[this] and [other]" can be expressed as "X requires Y which requires
  /// Z", this returns that expression.
  ///
  /// Otherwise, this returns `null`.
  String? _tryRequiresThrough(
    Incompatibility other, [
    Map<String, PackageDetail>? details,
    int? thisLine,
    int? otherLine,
  ]) {
    if (terms.length == 1 || other.terms.length == 1) return null;

    final thisNegative = _singleTermWhere((term) => !term.isPositive);
    final otherNegative = other._singleTermWhere((term) => !term.isPositive);
    if (thisNegative == null && otherNegative == null) return null;

    final thisPositive = _singleTermWhere((term) => term.isPositive);
    final otherPositive = other._singleTermWhere((term) => term.isPositive);

    Incompatibility prior;
    Term priorNegative;
    int? priorLine;
    Incompatibility latter;
    int? latterLine;
    if (thisNegative != null &&
        otherPositive != null &&
        thisNegative.package.name == otherPositive.package.name &&
        thisNegative.inverse.satisfies(otherPositive)) {
      prior = this;
      priorNegative = thisNegative;
      priorLine = thisLine;
      latter = other;
      latterLine = otherLine;
    } else if (otherNegative != null &&
        thisPositive != null &&
        otherNegative.package.name == thisPositive.package.name &&
        otherNegative.inverse.satisfies(thisPositive)) {
      prior = other;
      priorNegative = otherNegative;
      priorLine = otherLine;
      latter = this;
      latterLine = thisLine;
    } else {
      return null;
    }

    final priorPositives = prior.terms.where((term) => term.isPositive);

    final buffer = StringBuffer();
    if (priorPositives.length > 1) {
      final priorString =
          priorPositives.map((term) => _terse(term, details)).join(' or ');
      buffer.write('if $priorString then ');
    } else {
      final verb = prior.cause is DependencyIncompatibilityCause
          ? 'depends on'
          : 'requires';
      buffer.write('${_terse(priorPositives.first, details, allowEvery: true)} '
          '$verb ');
    }

    buffer.write(_terse(priorNegative, details));
    if (priorLine != null) buffer.write(' ($priorLine)');
    buffer.write(' which ');

    if (latter.cause is DependencyIncompatibilityCause) {
      buffer.write('depends on ');
    } else {
      buffer.write('requires ');
    }

    buffer.write(
      latter.terms
          .where((term) => !term.isPositive)
          .map((term) => _terse(term, details))
          .join(' or '),
    );

    if (latterLine != null) buffer.write(' ($latterLine)');

    return buffer.toString();
  }

  /// If "[this] and [other]" can be expressed as "X requires Y which is
  /// forbidden", this returns that expression.
  ///
  /// Otherwise, this returns `null`.
  String? _tryRequiresForbidden(
    Incompatibility other, [
    Map<String, PackageDetail>? details,
    int? thisLine,
    int? otherLine,
  ]) {
    if (terms.length != 1 && other.terms.length != 1) return null;

    Incompatibility prior;
    Incompatibility latter;
    int? priorLine;
    int? latterLine;
    if (terms.length == 1) {
      prior = other;
      latter = this;
      priorLine = otherLine;
      latterLine = thisLine;
    } else {
      prior = this;
      latter = other;
      priorLine = thisLine;
      latterLine = otherLine;
    }

    final negative = prior._singleTermWhere((term) => !term.isPositive);
    if (negative == null) return null;
    if (!negative.inverse.satisfies(latter.terms.first)) return null;

    final positives = prior.terms.where((term) => term.isPositive);

    final buffer = StringBuffer();
    if (positives.length > 1) {
      final priorString =
          positives.map((term) => _terse(term, details)).join(' or ');
      buffer.write('if $priorString then ');
    } else {
      buffer.write(_terse(positives.first, details, allowEvery: true));
      buffer.write(
        prior.cause is DependencyIncompatibilityCause
            ? ' depends on '
            : ' requires ',
      );
    }

    if (latter.cause is UnknownSourceIncompatibilityCause) {
      final package = latter.terms.first.package;
      buffer.write('${package.name} ');
      if (priorLine != null) buffer.write('($priorLine) ');
      buffer.write('from unknown source "${package.source}"');
      if (latterLine != null) buffer.write(' ($latterLine)');
      return buffer.toString();
    }

    buffer.write('${_terse(latter.terms.first, details)} ');
    if (priorLine != null) buffer.write('($priorLine) ');

    if (latter.cause is SdkIncompatibilityCause) {
      final cause = latter.cause as SdkIncompatibilityCause;
      if (cause.noNullSafetyCause) {
        buffer.write('which doesn\'t support null safety');
      } else {
        buffer.write('which requires ');
        if (!cause.sdk.isAvailable) {
          buffer.write('the ${cause.sdk.name} SDK');
        } else {
          if (cause.sdk.name != 'Dart') buffer.write('${cause.sdk.name} ');
          buffer.write('SDK version ${cause.constraint}');
        }
      }
    } else if (latter.cause is NoVersionsIncompatibilityCause) {
      buffer.write("which doesn't match any versions");
    } else if (latter.cause is PackageNotFoundIncompatibilityCause) {
      buffer.write("which doesn't exist "
          '(${(latter.cause as PackageNotFoundIncompatibilityCause).exception.message})');
    } else {
      buffer.write('which is forbidden');
    }

    if (latterLine != null) buffer.write(' ($latterLine)');

    return buffer.toString();
  }

  /// If exactly one term in this incompatibility matches [filter], returns that
  /// term.
  ///
  /// Otherwise, returns `null`.
  Term? _singleTermWhere(bool Function(Term) filter) {
    Term? found;
    for (var term in terms) {
      if (!filter(term)) continue;
      if (found != null) return null;
      found = term;
    }
    return found;
  }

  /// Returns a terse representation of [term]'s package ref.
  String _terseRef(Term term, Map<String, PackageDetail>? details) =>
      term.package
          .toRef()
          .toString(details == null ? null : details[term.package.name]);

  /// Returns a terse representation of [term]'s package.
  ///
  /// If [allowEvery] is `true`, this will return "every version of foo" instead
  /// of "foo any".
  String _terse(
    Term? term,
    Map<String, PackageDetail>? details, {
    bool allowEvery = false,
  }) {
    if (allowEvery && term!.constraint.isAny) {
      return 'every version of ${_terseRef(term, details)}';
    } else {
      return term!.package
          .toString(details == null ? null : details[term.package.name]);
    }
  }
}
