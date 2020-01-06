// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';

/// Handles the `global list` pub command.
class GlobalListCommand extends PubCommand {
  @override
  String get name => 'list';
  @override
  String get description => 'List globally activated packages.';
  @override
  String get invocation => 'pub global list';
  @override
  bool get allowTrailingOptions => false;
  @override
  bool get takesArguments => false;

  @override
  void run() {
    globals.listActivePackages();
  }
}
