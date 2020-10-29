// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/token.dart';
import 'package:pub_semver/pub_semver.dart';

/// A Dart language version as defined by
/// https://github.com/dart-lang/language/blob/master/accepted/future-releases/language-versioning/feature-specification.md
class LanguageVersion implements Comparable<LanguageVersion> {
  final int major;
  final int minor;

  const LanguageVersion(this.major, this.minor);

  /// The language version implied by a Dart sdk version.
  factory LanguageVersion.fromVersion(Version version) =>
      LanguageVersion(version.major, version.minor);

  /// The language version implied by a Dart sdk version range.
  ///
  /// Throws if the versionRange has no lower bound.
  factory LanguageVersion.fromVersionRange(VersionRange range) {
    final min = range.min;
    if (min == null) {
      // TODO(sigurdm): is this right?
      throw ArgumentError(
          'Version range with no lower bound does not imply a language version');
    }
    return LanguageVersion(min.major, min.minor);
  }

  /// The language version implied by a Dart sdk version.
  factory LanguageVersion.fromLanguageVersionToken(
          LanguageVersionToken version) =>
      LanguageVersion(version.major, version.minor);

  bool get supportsNullSafety => this >= firstVersionWithNullSafety;

  @override
  int compareTo(LanguageVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    return minor.compareTo(other.minor);
  }

  bool operator <(LanguageVersion other) => compareTo(other) < 0;
  bool operator >(LanguageVersion other) => compareTo(other) > 0;
  bool operator <=(LanguageVersion other) => compareTo(other) <= 0;
  bool operator >=(LanguageVersion other) => compareTo(other) >= 0;

  static const firstVersionWithNullSafety = LanguageVersion(2, 12);

  @override
  String toString() => '$major.$minor';
}
