// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'package:args/command_runner.dart';
import 'src/pub_embeddable_command.dart';
export 'src/executable.dart'
    show getExecutableForCommand, CommandResolutionFailedException;

/// Returns a [Command] for pub functionality that can be used by an embedding
/// CommandRunner.
Command<int> pubCommand() => PubEmbeddableCommand();
