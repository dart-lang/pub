// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'barback.dart';

/// Handles the `serve` pub command.
class ServeCommand extends BarbackCommand {
  String get name => "serve";
  String get description => 'Run a local web development server.\n\n'
      'By default, this serves "web/" and "test/", but an explicit list of \n'
      'directories to serve can be provided as well.';
}
