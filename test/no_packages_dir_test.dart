// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  forBothPubGetAndUpgrade((command) {
    test('does not touch directories named "packages"', () async {
      await d.dir(appPath, [
        d.appPubspec(),
        d.dir('packages'),
        d.dir('bin/packages'),
        d.dir('bin/subdir/packages'),
        d.dir('lib/packages')
      ]).create();

      await pubCommand(command);

      await d.dir(appPath, [
        d.dir('packages'),
        d.dir('bin/packages'),
        d.dir('bin/subdir/packages'),
        d.dir('lib/packages')
      ]).validate();
    });
  });
}
