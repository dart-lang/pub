// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Windows doesn't support sending signals.
// TODO(sigurdm): Test this when vm-args are provided.
// This test doesn't work when we subprocess instead of an isolate
// in `pub run`. Now signals only work as expected when sent to the process
// group. And this seems hard to emulate in a test.
@TestOn('!windows')
import 'dart:io';

import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

const _catchableSignals = [
  ProcessSignal.sighup,
  ProcessSignal.sigterm,
  ProcessSignal.sigusr1,
  ProcessSignal.sigusr2,
  ProcessSignal.sigwinch,
];

const _script = """
import 'dart:io';

main() {
  ProcessSignal.sighup.watch().first.then(print);
  ProcessSignal.sigterm.watch().first.then(print);
  ProcessSignal.sigusr1.watch().first.then(print);
  ProcessSignal.sigusr2.watch().first.then(print);
  ProcessSignal.sigwinch.watch().first.then(print);

  print("ready");
}
""";

void main() {
  test('forwards signals to the inner script', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', _script)])
    ]).create();

    await pubGet();
    var pub = await pubRun(args: ['bin/script']);

    await expectLater(pub.stdout, emitsThrough('ready'));
    for (var signal in _catchableSignals) {
      pub.signal(signal);
      await expectLater(pub.stdout, emits(signal.toString()));
    }

    await pub.kill();
  });
}
