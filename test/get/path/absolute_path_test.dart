// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('path dependency with absolute path', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': path.join(d.sandbox, 'foo')}
      })
    ]).create();

    await pubGet();

    await d.appPackagesFile({'foo': path.join(d.sandbox, 'foo')}).validate();
  });
}
