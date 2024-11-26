// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
import 'workspace_list.dart';

class WorkspaceCommand extends PubCommand {
  @override
  String get description => 'Work with the pub workspace.';

  @override
  String get name => 'workspace';

  WorkspaceCommand() {
    addSubcommand(WorkspaceListCommand());
  }
}
