// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:io';

import 'package:pub/src/path.dart';
import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

const _inactivePubBinStub = '''
# This file was created by pub v0.1.2-3.
# Package: pub
# Version: 1.0.0
# Executable: bar
# Script: bar
# Note: café
''';

const _foreignBinStub = '''
#!/usr/bin/env sh
echo before-marker
# This file was created by pub v0.1.2-3.
# Package: pub
# Executable: bar
# Script: bar
echo not-pub
''';

const _malformedPubBinStub = '''
# This file was created by pub v0.1.2-3.
# Package: pub
# Package: other
# Version: 1.0.0
# Executable: bar
# Script: bar
''';

const _crossFamilyBinStub = '''
#!/usr/bin/env sh
rem This file was created by pub v0.1.2-3.
rem Package: pub
rem Version: 1.0.0
rem Executable: bar
rem Script: bar
''';

void main() {
  test('does not overwrite an existing binstub', () async {
    await d.dir('foo', [
      d.pubspec({
        'name': 'foo',
        'executables': {'foo': 'foo', 'collide1': 'foo', 'collide2': 'foo'},
      }),
      d.dir('bin', [d.file('foo.dart', "main() => print('ok');")]),
    ]).create();

    await d.dir('bar', [
      d.pubspec({
        'name': 'bar',
        'executables': {'bar': 'bar', 'collide1': 'bar', 'collide2': 'bar'},
      }),
      d.dir('bin', [d.file('bar.dart', "main() => print('ok');")]),
    ]).create();

    await runPub(args: ['global', 'activate', '-spath', '../foo']);

    final pub = await startPub(
      args: ['global', 'activate', '-spath', '../bar'],
    );
    expect(pub.stdout, emitsThrough('Installed executable bar.'));
    expect(
      pub.stderr,
      emits('Executable collide1 was already installed from foo.'),
    );
    expect(
      pub.stderr,
      emits('Executable collide2 was already installed from foo.'),
    );
    expect(
      pub.stderr,
      emits(
        'Deactivate the other package(s) or activate bar using '
        '--overwrite.',
      ),
    );
    await pub.shouldExit();

    await d.dir(cachePath, [
      d.dir('bin', [
        d.file(binStubName('foo'), contains('foo:foo')),
        d.file(binStubName('bar'), contains('bar:bar')),
        d.file(binStubName('collide1'), contains('foo:foo')),
        d.file(binStubName('collide2'), contains('foo:foo')),
      ]),
    ]).validate();
  });

  test('overwrites a binstub owned by an inactive package', () async {
    await d.dir('bar', [
      d.pubspec({
        'name': 'bar',
        'executables': {'bar': 'bar'},
      }),
      d.dir('bin', [d.file('bar.dart', "main() => print('ok');")]),
    ]).create();

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('bar'), _inactivePubBinStub)]),
    ]).create();
    File(
      p.join(d.sandbox, cachePath, 'bin', binStubName('bar')),
    ).writeAsStringSync(_inactivePubBinStub, encoding: const SystemEncoding());

    await runPub(
      args: ['global', 'activate', '-spath', '../bar'],
      output: contains('Installed executable bar.'),
    );

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('bar'), contains('bar:bar'))]),
    ]).validate();
  });

  test('preserves a foreign file containing binstub properties', () async {
    await d.dir('bar', [
      d.pubspec({
        'name': 'bar',
        'executables': {'bar': 'bar'},
      }),
      d.dir('bin', [d.file('bar.dart', "main() => print('ok');")]),
    ]).create();

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('bar'), _crossFamilyBinStub)]),
    ]).create();

    await runPub(
      args: ['global', 'activate', '-spath', '../bar'],
      error: contains(
        'Executable bar already exists and was not installed by pub.',
      ),
    );

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('bar'), _crossFamilyBinStub)]),
    ]).validate();
  });

  test('overwrites a malformed pub binstub', () async {
    await d.dir('bar', [
      d.pubspec({
        'name': 'bar',
        'executables': {'bar': 'bar'},
      }),
      d.dir('bin', [d.file('bar.dart', "main() => print('ok');")]),
    ]).create();

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('bar'), _malformedPubBinStub)]),
    ]).create();

    await runPub(
      args: ['global', 'activate', '-spath', '../bar'],
      output: contains('Installed executable bar.'),
    );

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('bar'), contains('bar:bar'))]),
    ]).validate();
  });

  test('overwrites a foreign file with --overwrite', () async {
    await d.dir('bar', [
      d.pubspec({
        'name': 'bar',
        'executables': {'bar': 'bar'},
      }),
      d.dir('bin', [d.file('bar.dart', "main() => print('ok');")]),
    ]).create();

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('bar'), _foreignBinStub)]),
    ]).create();

    await runPub(
      args: ['global', 'activate', '-spath', '../bar', '--overwrite'],
      output: contains('Installed executable bar.'),
      error: contains('Replaced bar, which was not installed by pub.'),
    );

    await d.dir(cachePath, [
      d.dir('bin', [d.file(binStubName('bar'), contains('bar:bar'))]),
    ]).validate();
  });
}
