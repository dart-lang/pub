// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:pub/src/io.dart';
import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test(
    'pub token add creates pub-tokens.json with mode 0600 and dir with 0700',
    () async {
      await runPub(
        args: ['token', 'add', 'https://server.demo/'],
        input: ['auth-token'],
      );

      await d.tokensFile({
        'version': 1,
        'hosted': [
          {'url': 'https://server.demo', 'token': 'auth-token'},
        ],
      }).validate();

      if (Platform.isLinux || Platform.isMacOS) {
        final tokensFilePath = p.join(
          d.sandbox,
          configPath,
          'dart',
          'pub-tokens.json',
        );
        final dartDirPath = p.join(d.sandbox, configPath, 'dart');

        final fileMode = File(tokensFilePath).statSync().mode & 0x1ff;
        expect(
          fileMode,
          equals(384), // 0600 in octal
          reason: 'pub-tokens.json should have owner-only permissions (0600)',
        );

        final dirMode = Directory(dartDirPath).statSync().mode & 0x1ff;
        expect(
          dirMode,
          equals(448), // 0700 in octal
          reason: 'dart config dir should have owner-only permissions (0700)',
        );
      }
    },
  );

  test(
    'pub token list tightens permissions on existing pub-tokens.json to 0600',
    () async {
      await d.tokensFile({
        'version': 1,
        'hosted': [
          {'url': 'https://server.demo', 'token': 'auth-token'},
        ],
      }).create();

      if (Platform.isLinux || Platform.isMacOS) {
        final tokensFilePath = p.join(
          d.sandbox,
          configPath,
          'dart',
          'pub-tokens.json',
        );
        final dartDirPath = p.join(d.sandbox, configPath, 'dart');

        // Intentionally make them world-readable/traversable (0644 / 0755)
        chmod(420, tokensFilePath); // 0644
        chmod(493, dartDirPath); // 0755

        expect(File(tokensFilePath).statSync().mode & 0x1ff, equals(420));
        expect(Directory(dartDirPath).statSync().mode & 0x1ff, equals(493));

        // Running any command that loads tokens should tighten permissions
        await runPub(args: ['token', 'list']);

        expect(
          File(tokensFilePath).statSync().mode & 0x1ff,
          equals(384), // 0600
          reason: 'Existing pub-tokens.json should be tightened to 0600',
        );
        expect(
          Directory(dartDirPath).statSync().mode & 0x1ff,
          equals(448), // 0700
          reason: 'Containing dart config dir should be tightened to 0700',
        );
      }
    },
  );
}
