// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/package_name.dart';
import 'package:pub/src/solver/incompatibility.dart';
import 'package:pub/src/solver/incompatibility_cause.dart';
import 'package:pub/src/solver/reformat_ranges.dart';
import 'package:pub/src/solver/term.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  final description = ResolvedHostedDescription(
    HostedDescription('foo', 'https://pub.dev'),
    sha256: null,
  );
  test('reformatMax when max has a build identifier', () {
    expect(
      reformatMax(
        [PackageId('abc', Version.parse('1.2.3'), description)],
        VersionRange(
          min: Version.parse('0.2.4'),
          max: Version.parse('1.2.4'),
          alwaysIncludeMaxPreRelease: true,
        ),
      ),
      equals((Version.parse('1.2.4-0'), false)),
    );
    expect(
      reformatMax(
        [PackageId('abc', Version.parse('1.2.4-3'), description)],
        VersionRange(
          min: Version.parse('0.2.4'),
          max: Version.parse('1.2.4'),
          alwaysIncludeMaxPreRelease: true,
        ),
      ),
      equals((Version.parse('1.2.4-3'), true)),
    );
    expect(
      reformatMax(
        [],
        VersionRange(
          max: Version.parse('1.2.4+1'),
          alwaysIncludeMaxPreRelease: true,
        ),
      ),
      equals(null),
    );
  });

  test('reformatRanges reformats each range of a VersionUnion', () {
    final ref = PackageRef('foo', HostedDescription('foo', 'https://pub.dev'));
    // The complement of a single version, as produced for a forbidden version.
    final union = VersionConstraint.any.difference(Version.parse('2.0.0'));
    expect(union.toString(), '<2.0.0-∞ or >2.0.0');

    final reformatted = reformatRanges(
      {},
      Incompatibility([
        Term(ref.withConstraint(union), true),
      ], PackageVersionForbiddenCause()),
    );
    expect(
      reformatted.terms.single.package.constraint.toString(),
      '<2.0.0 or >2.0.0',
    );
  });
}
