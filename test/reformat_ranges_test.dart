// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:pub/src/package_name.dart';
import 'package:pub/src/solver/reformat_ranges.dart';
import 'package:pub/src/utils.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('reformatMax when max has a build identifier', () {
    expect(
      reformatMax(
        [PackageId('abc', null, Version.parse('1.2.3'), null)],
        VersionRange(
          min: Version.parse('0.2.4'),
          max: Version.parse('1.2.4'),
          alwaysIncludeMaxPreRelease: true,
        ),
      ),
      equals(
        Pair(
          Version.parse('1.2.4-0'),
          false,
        ),
      ),
    );
    expect(
      reformatMax(
        [PackageId('abc', null, Version.parse('1.2.4-3'), null)],
        VersionRange(
          min: Version.parse('0.2.4'),
          max: Version.parse('1.2.4'),
          alwaysIncludeMaxPreRelease: true,
        ),
      ),
      equals(
        Pair(
          Version.parse('1.2.4-3'),
          true,
        ),
      ),
    );
    expect(
        reformatMax(
          [],
          VersionRange(
            max: Version.parse('1.2.4+1'),
            alwaysIncludeMaxPreRelease: true,
          ),
        ),
        equals(null));
  });
}
