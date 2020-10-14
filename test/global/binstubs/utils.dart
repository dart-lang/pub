// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../test_pub.dart';

/// The buildbots do not have the Dart SDK (containing "dart" and "pub") on
/// their PATH, so we need to spawn the binstub process with a PATH that
/// explicitly includes it.
///
/// The `pub`/`pub.bat` command on the PATH will be the one in tool/test-bin not
/// the one from the sdk.
Map getEnvironment() {
  var binDir = p.dirname(Platform.resolvedExecutable);
  var separator = Platform.isWindows ? ';' : ':';
  var pubBin = p.absolute('tool', 'test-bin');
  var path =
      "$pubBin$separator${Platform.environment["PATH"]}$separator$binDir";

  var environment = getPubTestEnvironment();
  environment['PATH'] = path;
  return environment;
}
