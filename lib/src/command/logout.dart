// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../command.dart';
import '../oauth2.dart' as oauth2;

/// Handles the `logout` pub command.
class LogoutCommand extends PubCommand {
  String get name => "logout";
  String get description => 'Log out of pub.dartlang.org.';
  String get invocation => 'pub logout';

  LogoutCommand();

  /// The URL of the server to interact with.
  Uri get server {
    // An explicit argument takes precedence.
    if (argResults.wasParsed('server')) {
      return Uri.parse(argResults['server']);
    }

    // Otherwise, use the one specified in the pubspec (if any).
    if (entrypoint?.root?.pubspec?.publishTo != null) {
      return Uri.parse(entrypoint.root.pubspec.publishTo);
    }

    // Otherwise, use the default.
    return Uri.parse(cache.sources.hosted.defaultUrl);
  }

  Future run() async {
    oauth2.logout(server, cache);
  }
}
