import 'dart:io';

import 'package:checks/checks.dart';
import 'package:pub/src/dart.dart';
import 'package:pub/src/exceptions.dart';
import 'package:pub/src/log.dart';
import 'package:test/test.dart';

import 'descriptor.dart';

String outputPath() => '$sandbox/output/snapshot';
String incrementalDillPath() => '${outputPath()}.incremental';

// A quite big program is needed for the caching to be an actual advantage.
FileDescriptor foo = file('foo.dart', '''
foo() {
  ${List.generate(500000, (index) => 'print("$index");').join('\n')}
}
  ''');

FileDescriptor workingMain = file(
  'main.dart',
  '''
import 'foo.dart';

main() async {
  foo();
}
''',
);

FileDescriptor brokenMain = file(
  'main.dart',
  '''
import 'foo.dart';
yadda yadda
main() asyncc {
  foo();
}
''',
);

Future<Duration> timeCompilation(
  String executable, {
  bool fails = false,
}) async {
  final s = Stopwatch()..start();
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
  return s.elapsed;
}

void main() {
  test('Precompilation is much faster second time and removes old artifacts',
      () async {
    await dir('app', [
      workingMain,
      foo,
      packageConfigFile([]),
    ]).create();
    final first = await timeCompilation(path('app/main.dart'));
    check(
      because: 'Should not leave a stray directory.',
      File(incrementalDillPath()).existsSync(),
    ).isFalse();
    check(File(outputPath()).existsSync()).isTrue();

    // Do a second compilation to compare the compile times, it should be much
    // faster because it can reuse the compiled data in the dill file.
    final second = await timeCompilation(path('app/main.dart'));
    check(first).isGreaterThan(second * 2);

    // Now create an error to test that the output is placed at a different
    // location.
    await dir('app', [
      brokenMain,
      foo,
      packageConfigFile([]),
    ]).create();
    final afterErrors =
        await timeCompilation(path('app/main.dart'), fails: true);
    check(File(incrementalDillPath()).existsSync()).isTrue();
    check(File(outputPath()).existsSync()).isFalse();
    check(first).isGreaterThan(afterErrors * 2);

    // Fix the error, and check that we still use the cached output to improve
    // compile times.
    await dir('app', [
      workingMain,
    ]).create();
    final afterFix = await timeCompilation(path('app/main.dart'));
    // The output from the failed compilation should now be gone.
    check(File('${outputPath()}.incremental').existsSync()).isFalse();
    check(File(outputPath()).existsSync()).isTrue();
    check(first).isGreaterThan(afterFix * 2);
  });
}
