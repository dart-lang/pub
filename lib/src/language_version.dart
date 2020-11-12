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
  factory LanguageVersion.fromVersion(Version version) {
    ArgumentError.checkNotNull(version, 'version');
    return LanguageVersion(version.major, version.minor);
  }

  /// The language version implied by a Dart SDK constraint in `pubspec.yaml`.
  /// (this is `environment: {sdk: '>=2.0.0 <3.0.0'}` from `pubspec.yaml`)
  ///
  /// Fallbacks to [defaultLanguageVersion] if there is no [sdkConstraint] or
  /// the [sdkConstraint] has no lower-bound.
  factory LanguageVersion.fromSdkConstraint(VersionConstraint sdkConstraint) {
    if (sdkConstraint is VersionRange && sdkConstraint.min != null) {
      return LanguageVersion.fromVersion(sdkConstraint.min);
    }
    return defaultLanguageVersion;
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

  static const defaultLanguageVersion = LanguageVersion(2, 7);
  static const firstVersionWithNullSafety = LanguageVersion(2, 12);

  @override
  String toString() => '$major.$minor';
}
