// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library for utility functions for dealing with isolates.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Like [Isolate.spawnUri], except that this only returns once the Isolate has
/// exited.
///
/// If the isolate produces an unhandled exception, it's printed to stderr and
/// the [exitCode] variable is set to 255.
Future<int> runUri(
  Uri url,
  List<String> args,
  Object message, {
  bool buffered = false,
  bool? enableAsserts,
  bool automaticPackageResolution = false,
  Uri? packageConfig,
}) async {
  final errorPort = ReceivePort();
  final exitPort = ReceivePort();

  await Isolate.spawnUri(
    url,
    args,
    message,
    checked: enableAsserts,
    automaticPackageResolution: automaticPackageResolution,
    packageConfig: packageConfig,
    onError: errorPort.sendPort,
    onExit: exitPort.sendPort,
  );

  final subscription = errorPort.listen((list) {
    stderr.writeln('Unhandled exception:');
    stderr.writeln((list as List)[0]);
    stderr.write(list[1]);
    exitCode = 255;
  });
  try {
    await exitPort.first;
  } finally {
    await subscription.cancel();
  }
  return exitCode;
}
