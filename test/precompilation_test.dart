// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:pub/src/dart.dart';
import 'package:pub/src/exceptions.dart';
import 'package:pub/src/log.dart';
import 'package:test/test.dart';

import 'descriptor.dart';

String outputPath() => '$sandbox/output/snapshot';
String incrementalDillPath() => '${outputPath()}.incremental';

// Adjacent string literals ensure that the contiguous string 'original_value'
// only appears in the compiled Kernel constant table of the .dill file, while
// the embedded source table (uriToSource) contains "'original_' 'value'".
FileDescriptor foo = file('foo.dart', '''
String foo() => 'original_' 'value';
''');

FileDescriptor workingMain = file('main.dart', '''
import 'foo.dart';

void main() {
  print(foo());
}
''');

FileDescriptor brokenMain = file('main.dart', '''
import 'foo.dart';
yadda yadda
void main() asyncc {
  print(foo());
}
''');

Future<void> runPrecompile(String executable, {bool fails = false}) async {
  verbosity = Verbosity.none;
  Future<void> compile() async {
    await precompile(
      executablePath: executable,
      name: 'abc',
      outputPath: outputPath(),
      packageConfigPath: path('app/.dart_tool/package_config.json'),
    );
  }

  if (fails) {
    await check(compile()).throws<ApplicationException>();
  } else {
    await compile();
  }
  verbosity = Verbosity.normal;
}

/// Replaces the single occurrence of [from] with [to] in the compiled `.dill`
/// file at [dillPath].
///
/// Because `foo.dart` uses adjacent string literals (`'original_' 'value'`),
/// patching `'original_value'` to `'cached_version'` modifies only the compiled
/// Kernel constant table while leaving the embedded `uriToSource` bytes
/// matching `foo.dart` on disk. Subsequent incremental compilations that reuse
/// the cached kernel for `foo.dart` will preserve `'cached_version'`, whereas a
/// cold compilation from source will produce `'original_value'`.
void patchCompiledConstant(String dillPath, String from, String to) {
  final needle = utf8.encode(from);
  final replacement = utf8.encode(to);
  check(needle.length).equals(replacement.length);

  final bytes = File(dillPath).readAsBytesSync();
  final matches = <int>[];
  for (var i = 0; i <= bytes.length - needle.length; i++) {
    var found = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) matches.add(i);
  }
  check(matches).length.equals(1);
  final offset = matches.single;
  bytes.setRange(offset, offset + replacement.length, replacement);
  File(dillPath).writeAsBytesSync(bytes);
}

String runSnapshot() {
  final result = Process.runSync(Platform.resolvedExecutable, [outputPath()]);
  check(result.exitCode).equals(0);
  return (result.stdout as String).trim();
}

void main() {
  test('Precompilation reuses cached dill on subsequent runs '
      'and removes old artifacts', () async {
    await dir('app', [workingMain, foo, packageConfigFile([])]).create();
    await runPrecompile(path('app/main.dart'));
    check(
      because: 'Should not leave a stray directory.',
      File(incrementalDillPath()).existsSync(),
    ).isFalse();
    check(File(outputPath()).existsSync()).isTrue();
    check(runSnapshot()).equals('original_value');

    patchCompiledConstant(outputPath(), 'original_value', 'cached_version');
    check(runSnapshot()).equals('cached_version');

    // A second compilation should reuse the compiled library for `foo.dart`
    // from `outputPath()`.
    await runPrecompile(path('app/main.dart'));
    check(runSnapshot()).equals('cached_version');

    // Introduce an error in `main.dart` to test that the incremental dill is
    // placed at `incrementalDillPath()` and `outputPath()` is removed.
    await dir('app', [brokenMain]).create();
    await runPrecompile(path('app/main.dart'), fails: true);
    check(File(incrementalDillPath()).existsSync()).isTrue();
    check(File(outputPath()).existsSync()).isFalse();

    // Fix the error, and check that compilation initializes from
    // `incrementalDillPath()`, reuses the cached kernel for `foo.dart`, and
    // deletes `incrementalDillPath()`.
    await dir('app', [workingMain]).create();
    await runPrecompile(path('app/main.dart'));
    check(File(incrementalDillPath()).existsSync()).isFalse();
    check(File(outputPath()).existsSync()).isTrue();
    check(runSnapshot()).equals('cached_version');
  });
}
