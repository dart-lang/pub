// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

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
      var cause = this.cause as ConflictCause;
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
    var byName = <String, Map<PackageRef, Term>>{};
    for (var term in terms) {
      var byRef = byName.putIfAbsent(term.package.name, () => {});
      var ref = term.package.toRef();
      if (byRef.containsKey(ref)) {
        byRef[ref] = byRef[ref].intersect(term);

        // If we have two terms that refer to the same package but have a null
        // intersection, they're mutually exclusive, making this incompatibility
        // irrelevant, since we already know that mutually exclusive version
        // ranges are incompatible. We should never derive an irrelevant
        // incompatibility.
        assert(byRef[ref] != null);
      } else {
        byRef[ref] = term;
      }
    }

    return Incompatibility._(
        byName.values.expand((byRef) {
          // If there are any positive terms for a given package, we can discard
          // any negative terms.
          var positiveTerms =
              byRef.values.where((term) => term.isPositive).toList();
          if (positiveTerms.isNotEmpty) return positiveTerms;

          return byRef.values;
        }).toList(),
        cause);
  }

  Incompatibility._(this.terms, this.cause);

  /// Returns a string representation of [this].
  ///
  /// If [details] is passed, it controls the amount of detail that's written
  /// for packages with the given names.
  @override
  String toString([Map<String, PackageDetail> details]) {
    if (cause == IncompatibilityCause.dependency) {
      assert(terms.length == 2);

      var depender = terms.first;
      var dependee = terms.last;
      assert(depender.isPositive);
      assert(!dependee.isPositive);

      return '${_terse(depender, details, allowEvery: true)} depends on '
          '${_terse(dependee, details)}';
    } else if (cause == IncompatibilityCause.useLatest) {
      assert(terms.length == 1);

      var forbidden = terms.last;
      assert(forbidden.isPositive);

      return 'the latest version of ${_terseRef(forbidden, details)} '
          '(${VersionConstraint.any.difference(forbidden.constraint)}) '
          'is required';
    } else if (cause is SdkCause) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);

      var cause = this.cause as SdkCause;
      var buffer = StringBuffer(
          '${_terse(terms.first, details, allowEvery: true)} requires ');
      if (!cause.sdk.isAvailable) {
        buffer.write('the ${cause.sdk.name} SDK');
      } else {
        if (cause.sdk.name != 'Dart') buffer.write(cause.sdk.name + ' ');
        buffer.write('SDK version ${cause.constraint}');
      }
      return buffer.toString();
    } else if (cause == IncompatibilityCause.noVersions) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);
      return 'no versions of ${_terseRef(terms.first, details)} '
          'match ${terms.first.constraint}';
    } else if (cause is PackageNotFoundCause) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);

      var cause = this.cause as PackageNotFoundCause;
      return "${_terseRef(terms.first, details)} doesn't exist "
          '(${cause.exception.message})';
    } else if (cause == IncompatibilityCause.unknownSource) {
      assert(terms.length == 1);
      assert(terms.first.isPositive);
      return '${terms.first.package.name} comes from unknown source '
          '"${terms.first.package.source}"';
    } else if (cause == IncompatibilityCause.root) {
      // [IncompatibilityCause.root] is only used when a package depends on the
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
      var term = terms.single;
      if (term.constraint.isAny) {
        return '${_terseRef(term, details)} is '
            "${term.isPositive ? 'forbidden' : 'required'}";
      } else {
        return '${_terse(term, details)} is '
            "${term.isPositive ? 'forbidden' : 'required'}";
      }
    }

    if (terms.length == 2) {
      var term1 = terms.first;
      var term2 = terms.last;
      if (term1.isPositive == term2.isPositive) {
        if (term1.isPositive) {
          var package1 = term1.constraint.isAny
              ? _terseRef(term1, details)
              : _terse(term1, details);
          var package2 = term2.constraint.isAny
              ? _terseRef(term2, details)
              : _terse(term2, details);
          return '$package1 is incompatible with $package2';
        } else {
          return 'either ${_terse(term1, details)} or '
              '${_terse(term2, details)}';
        }
      }
    }

    var positive = <String>[];
    var negative = <String>[];
    for (var term in terms) {
      (term.isPositive ? positive : negative).add(_terse(term, details));
    }

    if (positive.isNotEmpty && negative.isNotEmpty) {
      if (positive.length == 1) {
        var positiveTerm = terms.firstWhere((term) => term.isPositive);
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
  String andToString(Incompatibility other,
      [Map<String, PackageDetail> details, int thisLine, int otherLine]) {
    var requiresBoth = _tryRequiresBoth(other, details, thisLine, otherLine);
    if (requiresBoth != null) return requiresBoth;

    var requiresThrough =
        _tryRequiresThrough(other, details, thisLine, otherLine);
    if (requiresThrough != null) return requiresThrough;

    var requiresForbidden =
        _tryRequiresForbidden(other, details, thisLine, otherLine);
    if (requiresForbidden != null) return requiresForbidden;

    var buffer = StringBuffer(toString(details));
    if (thisLine != null) buffer.write(' $thisLine');
    buffer.write(' and ${other.toString(details)}');
    if (otherLine != null) buffer.write(' $thisLine');
    return buffer.toString();
  }

  /// If "[this] and [other]" can be expressed as "some package requires both X
  /// and Y", this returns that expression.
  ///
  /// Otherwise, this returns `null`.
  String _tryRequiresBoth(Incompatibility other,
      [Map<String, PackageDetail> details, int thisLine, int otherLine]) {
    if (terms.length == 1 || other.terms.length == 1) return null;

    var thisPositive = _singleTermWhere((term) => term.isPositive);
    if (thisPositive == null) return null;
    var otherPositive = other._singleTermWhere((term) => term.isPositive);
    if (otherPositive == null) return null;
    if (thisPositive.package != otherPositive.package) return null;

    var thisNegatives = terms
        .where((term) => !term.isPositive)
        .map((term) => _terse(term, details))
        .join(' or ');
    var otherNegatives = other.terms
        .where((term) => !term.isPositive)
        .map((term) => _terse(term, details))
        .join(' or ');

    var buffer =
        StringBuffer(_terse(thisPositive, details, allowEvery: true) + ' ');
    var isDependency = cause == IncompatibilityCause.dependency &&
        other.cause == IncompatibilityCause.dependency;
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
  String _tryRequiresThrough(Incompatibility other,
      [Map<String, PackageDetail> details, int thisLine, int otherLine]) {
    if (terms.length == 1 || other.terms.length == 1) return null;

    var thisNegative = _singleTermWhere((term) => !term.isPositive);
    var otherNegative = other._singleTermWhere((term) => !term.isPositive);
    if (thisNegative == null && otherNegative == null) return null;

    var thisPositive = _singleTermWhere((term) => term.isPositive);
    var otherPositive = other._singleTermWhere((term) => term.isPositive);

    Incompatibility prior;
    Term priorNegative;
    int priorLine;
    Incompatibility latter;
    int latterLine;
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

    var priorPositives = prior.terms.where((term) => term.isPositive);

    var buffer = StringBuffer();
    if (priorPositives.length > 1) {
      var priorString =
          priorPositives.map((term) => _terse(term, details)).join(' or ');
      buffer.write('if $priorString then ');
    } else {
      var verb = prior.cause == IncompatibilityCause.dependency
          ? 'depends on'
          : 'requires';
      buffer.write('${_terse(priorPositives.first, details, allowEvery: true)} '
          '$verb ');
    }

    buffer.write(_terse(priorNegative, details));
    if (priorLine != null) buffer.write(' ($priorLine)');
    buffer.write(' which ');

    if (latter.cause == IncompatibilityCause.dependency) {
      buffer.write('depends on ');
    } else {
      buffer.write('requires ');
    }

    buffer.write(latter.terms
        .where((term) => !term.isPositive)
        .map((term) => _terse(term, details))
        .join(' or '));

    if (latterLine != null) buffer.write(' ($latterLine)');

    return buffer.toString();
  }

  /// If "[this] and [other]" can be expressed as "X requires Y which is
  /// forbidden", this returns that expression.
  ///
  /// Otherwise, this returns `null`.
  String _tryRequiresForbidden(Incompatibility other,
      [Map<String, PackageDetail> details, int thisLine, int otherLine]) {
    if (terms.length != 1 && other.terms.length != 1) return null;

    Incompatibility prior;
    Incompatibility latter;
    int priorLine;
    int latterLine;
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

    var negative = prior._singleTermWhere((term) => !term.isPositive);
    if (negative == null) return null;
    if (!negative.inverse.satisfies(latter.terms.first)) return null;

    var positives = prior.terms.where((term) => term.isPositive);

    var buffer = StringBuffer();
    if (positives.length > 1) {
      var priorString =
          positives.map((term) => _terse(term, details)).join(' or ');
      buffer.write('if $priorString then ');
    } else {
      buffer.write(_terse(positives.first, details, allowEvery: true));
      buffer.write(prior.cause == IncompatibilityCause.dependency
          ? ' depends on '
          : ' requires ');
    }

    if (latter.cause == IncompatibilityCause.unknownSource) {
      var package = latter.terms.first.package;
      buffer.write('${package.name} ');
      if (priorLine != null) buffer.write('($priorLine) ');
      buffer.write('from unknown source "${package.source}"');
      if (latterLine != null) buffer.write(' ($latterLine)');
      return buffer.toString();
    }

    buffer.write('${_terse(latter.terms.first, details)} ');
    if (priorLine != null) buffer.write('($priorLine) ');

    if (latter.cause == IncompatibilityCause.useLatest) {
      var latest =
          VersionConstraint.any.difference(latter.terms.single.constraint);
      buffer.write('but the latest version ($latest) is required');
    } else if (latter.cause is SdkCause) {
      var cause = latter.cause as SdkCause;
      buffer.write('which requires ');
      if (!cause.sdk.isAvailable) {
        buffer.write('the ${cause.sdk.name} SDK');
      } else {
        if (cause.sdk.name != 'Dart') buffer.write(cause.sdk.name + ' ');
        buffer.write('SDK version ${cause.constraint}');
      }
    } else if (latter.cause == IncompatibilityCause.noVersions) {
      buffer.write("which doesn't match any versions");
    } else if (cause is PackageNotFoundCause) {
      buffer.write("which doesn't exist "
          '(${(cause as PackageNotFoundCause).exception.message})');
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
  Term _singleTermWhere(bool Function(Term) filter) {
    Term found;
    for (var term in terms) {
      if (!filter(term)) continue;
      if (found != null) return null;
      found = term;
    }
    return found;
  }

  /// Returns a terse representation of [term]'s package ref.
  String _terseRef(Term term, Map<String, PackageDetail> details) =>
      term.package
          .toRef()
          .toString(details == null ? null : details[term.package.name]);

  /// Returns a terse representation of [term]'s package.
  ///
  /// If [allowEvery] is `true`, this will return "every version of foo" instead
  /// of "foo any".
  String _terse(Term term, Map<String, PackageDetail> details,
      {bool allowEvery = false}) {
    if (allowEvery && term.constraint.isAny) {
      return 'every version of ${_terseRef(term, details)}';
    } else {
      return term.package
          .toString(details == null ? null : details[term.package.name]);
    }
  }
}
