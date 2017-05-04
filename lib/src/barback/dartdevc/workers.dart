// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:bazel_worker/driver.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

/// Manages a shared set of persistent analyzer workers.
final analyzerDriver = new BazelWorkerDriver(() => Process.start(
    p.join(sdkDir.path, 'bin', 'dartanalyzer'),
    ['--build-mode', '--persistent_worker']));

/// Manages a shared set of persistent dartdevc workers.
final dartdevcDriver = new BazelWorkerDriver(() => Process
    .start(p.join(sdkDir.path, 'bin', 'dartdevc'), ['--persistent_worker']));

final sdkDir = cli_util.getSdkDir();
