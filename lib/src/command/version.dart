// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import '../command.dart';
import '../log.dart' as log;
import '../sdk.dart';

/// Handles the `version` pub command.
class VersionCommand extends PubCommand {
  @override
  String get name => 'version';
  @override
  String get description => 'Print pub version.';
  @override
  String get argumentsDescription => '';

  @override
  Future<void> runProtected() async {
    log.message('Pub ${sdk.version}');
  }
}
