// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import '../command.dart';
import '../utils.dart';

/// Handles the `uploader` pub command.
class UploaderCommand extends PubCommand {
  @override
  String get name => 'uploader';
  @override
  String get description => 'Manage uploaders for a package on pub.dev.';
  @override
  String get argumentsDescription => '[options] {add/remove} <email>';
  @override
  String get docUrl => 'https://dart.dev/tools/pub/cmd/pub-uploader';

  @override
  bool get hidden => true;

  /// The URL of the package hosting server.
  Uri get server => Uri.parse(asString(argResults['server']));

  UploaderCommand() {
    argParser.addOption(
      'server',
      defaultsTo: Platform.environment['PUB_HOSTED_URL'] ?? 'https://pub.dev',
      help: 'The package server on which the package is hosted.\n',
      hide: true,
    );
    argParser.addOption(
      'package',
      help: 'The package whose uploaders will be modified.\n'
          '(defaults to the current package)',
    );
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Run this in the directory <dir>.',
      valueHelp: 'dir',
    );
  }

  @override
  Future<void> runProtected() async {
    String packageName = '<packageName>';
    try {
      packageName = entrypoint.root.name;
    } on Exception catch (_) {
      // Probably run without a pubspec.
      // Just print error below without a specific package name.
    }
    fail('''
Package uploaders are no longer managed from the command line.
Manage uploaders from:

https://pub.dev/packages/$packageName/admin
''');
  }
}
