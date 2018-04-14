// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'barback.dart';

/// Handles the `serve` pub command.
class ServeCommand extends BarbackCommand {
  String get name => "serve";
  String get description => "Deprecated command";
  bool get hidden => true;
}
