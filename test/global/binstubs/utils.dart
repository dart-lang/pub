// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../test_pub.dart';

/// The buildbots do not have the Dart SDK (containing "dart" and "pub") on
/// their PATH, so we need to spawn the binstub process with a PATH that
/// explicitly includes it.
Map getEnvironment() {
  // TODO(rnystrom): This doesn't do the right thing when running pub's tests
  // from pub's own repo instead of from within the Dart SDK repo. This always
  // sets up the PATH to point to the directory where the Dart VM was run from,
  // which will be unrelated to the path where pub itself is located when
  // running from pub's repo.
  //
  // However, pub's repo doesn't actually have the shell scripts required to
  // run "pub". Those live in the Dart SDK repo. One fix would be to make shell
  // scripts in pub's repo that can act like those scripts but invoke pub from
  // source from the pub repo.
  var binDir = p.dirname(Platform.executable);
  var separator = Platform.isWindows ? ';' : ':';
  var path = "${Platform.environment["PATH"]}$separator$binDir";

  var environment = getPubTestEnvironment();
  environment['PATH'] = path;
  return environment;
}
