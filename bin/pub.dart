// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub/src/command_runner.dart';
import 'package:pub/src/io.dart';

Future<void> main(List<String> arguments) async {
  await flushThenExit(await PubCommandRunner().run(arguments));
}
