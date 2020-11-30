// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'golden_file.dart';
import 'test_pub.dart';

Future<void> testCommandOutput(List<String> args, String goldenFilePath) async {
  final p = await startPub(args: args);
  final exitCode = await p.exitCode;

  final buffer = StringBuffer();
  buffer.writeln('[command]');
  buffer.writeln(['pub', ...args].join(' '));
  buffer.writeln('[stdout]');
  buffer.write((await p.stdout.rest.toList()).join('\n'));
  buffer.writeln('[stderr]');
  buffer.write((await p.stderr.rest.toList()).join('\n'));
  buffer.writeln('[exitCode]');
  buffer.writeln(exitCode);
  expectMatchesGoldenFile(buffer.toString(), goldenFilePath);
}

void main() {
  test('Usage exception for missing subcommand', () async {
    await testCommandOutput(['global'], 'test/goldens/usage_exception.txt');
  });
}
