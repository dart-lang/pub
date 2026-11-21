// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub/src/authentication/auth_helper.dart';
import 'package:pub/src/exceptions.dart';
import 'package:test/test.dart';

import '../descriptor.dart' as d;

void main() {
  final repository = Uri.parse('https://example.test/org/team/feed/');
  const context = (
    package: 'widgets',
    version: null,
    archive: null,
    attestations: null,
  );

  Future<AuthHelper> helper(String mode) async {
    await d.file('read.dart', r"""
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final input = jsonDecode(await utf8.decoder.bind(stdin).join());
  final action = input['action'];
  File(args.first + '.' + action).writeAsStringSync(jsonEncode(input) + '\n',
      mode: FileMode.append);
  if (args.last == 'structured' || args.last == 'raw') {
    stderr.write('sensitive diagnostics');
    stdout.write(args.last == 'structured' ? jsonEncode({
      'error': 'sign_in_required', 'message': 'Run\nrepo-helper login.',
    }) : 'sensitive output');
    exitCode = 2;
    return;
  }
  final now = DateTime.now().toUtc();
  stdout.write(jsonEncode(action == 'prove'
      ? {'proof': 'header.payload.signature'}
      : {'token': 'private-token', 'tokenType': args.last == 'proof' ? 'DPoP' : 'Bearer',
         'expiresAt': (args.last == 'expired' ? now.subtract(const Duration(hours: 1)) :
             now.add(const Duration(hours: 1))).toIso8601String()}));
}
""").create();
    return AuthHelper([
      Platform.resolvedExecutable,
      d.path('read.dart'),
      d.path('log'),
      mode,
    ]);
  }

  test(
    'coalesces concurrent reads but produces request-specific proofs',
    () async {
      final auth = await helper('proof');
      final first = repository.resolve('metadata?x=1');
      final second = repository.resolve('archive');
      final headers = await Future.wait([
        auth.headers(repository, context, 'GET', first),
        auth.headers(repository, context, 'GET', second),
      ]);
      expect(
        headers,
        everyElement({
          'authorization': 'DPoP private-token',
          'dpop': 'header.payload.signature',
        }),
      );
      final acquisition = jsonDecode(
        File(d.path('log.acquire')).readAsLinesSync().single,
      );
      expect(acquisition, {
        'protocolVersion': 1,
        'repository-url': repository.toString(),
        'interactive': false,
        'action': 'acquire',
        'operation': 'read',
        'package': 'widgets',
      });
      final proofs = File(
        d.path('log.prove'),
      ).readAsLinesSync().map((line) => jsonDecode(line) as Map);
      expect(
        proofs.map((entry) => entry['uri']),
        unorderedEquals([
          repository.resolve('metadata').toString(),
          second.toString(),
        ]),
      );
      expect(proofs.map((entry) => entry['method']), everyElement('GET'));
    },
  );

  for (final mode in ['structured', 'raw']) {
    test('reports $mode helper failure without exposing raw output', () async {
      final auth = await helper(mode);
      await expectLater(
        auth.headers(repository, context, 'GET', repository),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            mode == 'structured'
                ? 'Auth helper for $repository (exit 2): Run repo-helper login.'
                : 'Auth helper for $repository exited with code 2.',
          ),
        ),
      );
    });
  }

  test('rejects an already expired read grant', () async {
    final auth = await helper('expired');
    await expectLater(
      auth.headers(repository, context, 'GET', repository),
      throwsA(isA<DataException>()),
    );
  });
}
