// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'test_pub.dart';

void main() {
  test('running pub with no command displays usage', () {
    return runPub(args: [], output: """
        Pub is a package manager for Dart.

        Usage: pub <command> [arguments]

        Global options:
        -h, --help             Print this usage information.
            --version          Print pub version.
            --[no-]trace       Print debugging information when an error occurs.
            --verbosity        Control output verbosity.

                  [all]        Show all output including internal tracing messages.
                  [error]      Show only errors.
                  [io]         Also show IO operations.
                  [normal]     Show errors, warnings, and user messages.
                  [solver]     Show steps during version resolution.
                  [warning]    Show only errors and warnings.

        -v, --verbose          Shortcut for "--verbosity=all".

        Available commands:
          cache       Work with the system cache.
          deps        Print package dependencies.
          downgrade   Downgrade the current package's dependencies to oldest versions.
          get         Get the current package's dependencies.
          global      Work with global packages.
          logout      Log out of pub.dartlang.org.
          outdated    Analyze your dependencies to find which ones can be upgraded.
          publish     Publish the current package to pub.dartlang.org.
          run         Run an executable from a package.
          upgrade     Upgrade the current package's dependencies to latest versions.
          uploader    Manage uploaders for a package on pub.dartlang.org.
          version     Print pub version.

        Run "pub help <command>" for more information about a command.
        See https://dart.dev/tools/pub/cmd for detailed documentation.
        """);
  });

  test('running pub with just --version displays version', () {
    return runPub(args: ['--version'], output: 'Pub 0.1.2+3');
  });
}
