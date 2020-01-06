// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test('activating a path package installs dependencies', () async {
    await servePackages((builder) {
      builder.serve('bar', '1.0.0', deps: {'baz': 'any'});
      builder.serve('baz', '2.0.0');
    });

    await d.dir('foo', [
      d.libPubspec('foo', '0.0.0', deps: {'bar': 'any'}),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")])
    ]).create();

    var pub = await startPub(args: ['global', 'activate', '-spath', '../foo']);
    expect(pub.stdout, emitsThrough('Resolving dependencies...'));
    expect(pub.stdout, emitsThrough('Downloading bar 1.0.0...'));
    expect(pub.stdout, emitsThrough('Downloading baz 2.0.0...'));
    expect(pub.stdout, emitsThrough(startsWith('Activated foo 0.0.0 at path')));
    await pub.shouldExit();

    // Puts the lockfile in the linked package itself.
    await d.dir('foo', [
      d.file(
          'pubspec.lock',
          allOf([
            contains('bar'),
            contains('1.0.0'),
            contains('baz'),
            contains('2.0.0')
          ]))
    ]).validate();
  });
}
