// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Windows doesn't support sending signals.
@TestOn('!windows')
import 'dart:io';

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

const _catchableSignals = [
  ProcessSignal.sighup,
  ProcessSignal.sigterm,
  ProcessSignal.sigusr1,
  ProcessSignal.sigusr2,
  ProcessSignal.sigwinch,
];

const SCRIPT = """
import 'dart:io';

main() {
  ProcessSignal.SIGHUP.watch().first.then(print);
  ProcessSignal.SIGTERM.watch().first.then(print);
  ProcessSignal.SIGUSR1.watch().first.then(print);
  ProcessSignal.SIGUSR2.watch().first.then(print);
  ProcessSignal.SIGWINCH.watch().first.then(print);

  print("ready");
}
""";

void main() {
  test('forwards signals to the inner script', () async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir('bin', [d.file('script.dart', SCRIPT)])
    ]).create();

    await pubGet();
    var pub = await pubRunV2(args: ['myapp:script']);

    await expectLater(pub.stdout, emits('ready'));
    for (var signal in _catchableSignals) {
      pub.signal(signal);
      await expectLater(pub.stdout, emits(signal.toString()));
    }

    await pub.kill();
  });
}
