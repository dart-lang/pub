// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/token.dart';
import 'package:pub_semver/pub_semver.dart';

final _languageVersionPattern = RegExp(r'^(\d+)\.(\d+)$');

/// A Dart language version as defined by
/// https://github.com/dart-lang/language/blob/master/accepted/future-releases/language-versioning/feature-specification.md
class LanguageVersion implements Comparable<LanguageVersion> {
  final int major;
  final int minor;

  const LanguageVersion(this.major, this.minor);

  /// The language version implied by a Dart sdk version.
  factory LanguageVersion.fromVersion(Version version) {
    return LanguageVersion(version.major, version.minor);
  }

  /// Parse language version from string.
  factory LanguageVersion.parse(String languageVersion) {
    final m = _languageVersionPattern.firstMatch(languageVersion);
    if (m == null) {
      throw FormatException(
        'Invalid language version string',
        languageVersion,
      );
    }
    return LanguageVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
    );
  }

  /// The language version implied by a Dart SDK constraint in `pubspec.yaml`.
  /// (this is `environment: {sdk: '>=2.0.0 <3.0.0'}` from `pubspec.yaml`)
  ///
  /// Fallbacks to [defaultLanguageVersion] if there is no [sdkConstraint] or
  /// the [sdkConstraint] has no lower-bound.
  factory LanguageVersion.fromSdkConstraint(VersionConstraint? sdkConstraint) {
    if (sdkConstraint == null || sdkConstraint.isEmpty) {
      return defaultLanguageVersion;
    } else if (sdkConstraint is Version) {
      return LanguageVersion.fromVersion(sdkConstraint);
    } else if (sdkConstraint is VersionRange) {
      if (sdkConstraint.min != null) {
        return LanguageVersion.fromVersion(sdkConstraint.min!);
      }
      return defaultLanguageVersion;
    } else if (sdkConstraint is VersionUnion) {
      // `ranges` is non-empty and sorted.
      final min = sdkConstraint.ranges.first.min;
      if (min != null) {
        return LanguageVersion.fromVersion(min);
      }
      return defaultLanguageVersion;
    } else {
      throw ArgumentError('Unknown VersionConstraint type $sdkConstraint.');
    }
  }

  /// The language version implied by a Dart sdk version.
  factory LanguageVersion.fromLanguageVersionToken(
          LanguageVersionToken version) =>
      LanguageVersion(version.major, version.minor);

  bool get supportsNullSafety => this >= firstVersionWithNullSafety;

  /// Minimum language version at which short hosted syntax is supported.
  ///
  /// This allows `hosted` dependencies to be expressed as:
  /// ```yaml
  /// dependencies:
  ///   foo:
  ///     hosted: https://some-pub.com/path
  ///     version: ^1.0.0
  /// ```
  ///
  /// At older versions, `hosted` dependencies had to be a map with a `url` and
  /// a `name` key.
  bool get supportsShorterHostedSyntax =>
      this >= firstVersionWithShorterHostedSyntax;

  @override
  int compareTo(LanguageVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    return minor.compareTo(other.minor);
  }

  bool operator <(LanguageVersion other) => compareTo(other) < 0;
  bool operator >(LanguageVersion other) => compareTo(other) > 0;
  bool operator <=(LanguageVersion other) => compareTo(other) <= 0;
  bool operator >=(LanguageVersion other) => compareTo(other) >= 0;

  @override
  int get hashCode => major ^ minor;

  @override
  bool operator ==(Object other) =>
      other is LanguageVersion && other.minor == minor && other.major == major;

  static const defaultLanguageVersion = LanguageVersion(2, 7);
  static const firstVersionWithNullSafety = LanguageVersion(2, 12);
  static const firstVersionWithShorterHostedSyntax = LanguageVersion(2, 15);

  /// Transform language version to string that can be parsed with
  /// [LanguageVersion.parse].
  @override
  String toString() => '$major.$minor';

  Version firstStable() => Version(major, minor, 0);
}
