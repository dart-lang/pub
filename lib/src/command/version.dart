// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import '../log.dart' as log;
import '../sdk.dart';

/// Handles the `version` pub command.
class VersionCommand extends PubCommand {
  String get name => "version";
  String get description => "Print pub version.";
  String get invocation => "pub version";

  void run() {
    log.message("Pub ${sdk.version}");
  }
}
