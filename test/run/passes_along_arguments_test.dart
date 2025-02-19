// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const _script = '''
main(List<String> args) {
  print(args.join(" "));
}
''';

void main() {
  test('passes arguments to the spawned script', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('args.dart', _script)]),
    ]).create();

    await pubGet();

    // Use some args that would trip up pub's arg parser to ensure that it
    // isn't trying to look at them.
    final pub = await pubRun(
      args: ['bin/args', '--verbose', '-m', '--', 'help'],
    );

    expect(pub.stdout, emitsThrough('--verbose -m -- help'));
    await pub.shouldExit();
  });
}
