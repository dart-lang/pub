// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library for utility functions for dealing with isolates.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Like [Isolate.spanwUri], except that this only returns once the Isolate has
/// exited.
///
/// If the isolate produces an unhandled exception, it's printed to stderr and
/// the [exitCode] variable is set to 255.
///
/// If [buffered] is `true`, this uses [spawnBufferedUri] to spawn the isolate.
Future runUri(Uri url, List<String> args, Object message,
    {bool buffered = false,
    bool enableAsserts,
    bool automaticPackageResolution = false,
    Uri packageConfig}) async {
  var errorPort = ReceivePort();
  var exitPort = ReceivePort();

  await Isolate.spawnUri(url, args, message,
      checked: enableAsserts,
      automaticPackageResolution: automaticPackageResolution,
      packageConfig: packageConfig,
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort);

  errorPort.listen((list) {
    stderr.writeln('Unhandled exception:');
    stderr.writeln(list[0]);
    stderr.write(list[1]);
    exitCode = 255;
  });

  await exitPort.first;
}
