// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE d.file.

import 'package:test/test.dart';

import 'package:path/path.dart' as path;

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('path dependency when path is a file', () async {
    await d
        .dir('foo', [d.libDir('foo'), d.libPubspec('foo', '0.0.1')]).create();

    await d.file('dummy.txt', '').create();
    var dummyPath = path.join(d.sandbox, 'dummy.txt');

    await d.dir(appPath, [
      d.appPubspec({
        'foo': {'path': dummyPath}
      })
    ]).create();

    await pubGet(
        error: 'Path dependency for package foo must refer to a '
            'directory, not a file. Was "$dummyPath".');
  });
}
