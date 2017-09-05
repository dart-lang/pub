// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:bazel_worker/driver.dart';
import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

import '../log.dart';

String get _scriptExtension => Platform.isWindows ? '.bat' : '';

const _defaultMaxWorkers = 4;

const _maxWorkersEnvVar = 'PUB_MAX_WORKERS_PER_TASK';

final int _maxWorkersPerTask = int
    .parse(Platform.environment[_maxWorkersEnvVar] ?? '$_defaultMaxWorkers',
        onError: (value) {
  warning(yellow('Invalid value for $_maxWorkersEnvVar environment variable, '
      'expected an int but got `$value`. Falling back to default value '
      'of $_defaultMaxWorkers.'));
  return _defaultMaxWorkers;
});

/// Manages a shared set of persistent analyzer workers.
final analyzerDriver = new BazelWorkerDriver(
    () => Process.start(p.join(sdkDir, 'bin', 'dartanalyzer$_scriptExtension'),
        ['--build-mode', '--persistent_worker']),
    maxWorkers: _maxWorkersPerTask);

/// Manages a shared set of persistent dartdevc workers.
final dartdevcDriver = new BazelWorkerDriver(
    () => Process.start(p.join(sdkDir, 'bin', 'dartdevc$_scriptExtension'),
        ['--persistent_worker']),
    maxWorkers: _maxWorkersPerTask);

final sdkDir = cli_util.getSdkPath();
