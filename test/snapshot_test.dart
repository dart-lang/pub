// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  group('creates a snapshot', () {
    test('for an immediate dependency', () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.2.3',
        contents: [
          d.dir('bin', [
            d.file('hello.dart', "void main() => print('hello!');"),
            d.file('goodbye.dart', "void main() => print('goodbye!');"),
            d.file('shell.sh', 'echo shell'),
            d.dir('subdir', [
              d.file('sub.dart', "void main() => print('sub!');"),
            ]),
          ]),
        ],
      );

      await d.appDir(dependencies: {'foo': '1.2.3'}).create();

      await pubGet(
        args: ['--precompile'],
        output: allOf([
          contains('Built foo:hello.'),
          contains('Built foo:goodbye.'),
        ]),
      );

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
        d.dir('foo', [
          d.file('hello.dart-$versionSuffix.snapshot', contains('hello!')),
          d.file('goodbye.dart-$versionSuffix.snapshot', contains('goodbye!')),
          d.nothing('shell.sh-$versionSuffix.snapshot'),
          d.nothing('subdir'),
        ]),
      ]).validate();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits('hello!'));
      await process.shouldExit();

      process = await pubRun(args: ['foo:goodbye']);
      expect(process.stdout, emits('goodbye!'));
      await process.shouldExit();
    });

    test("for an immediate dependency that's also transitive", () async {
      await servePackages()
        ..serve(
          'foo',
          '1.2.3',
          contents: [
            d.dir('bin', [
              d.file('hello.dart', "void main() => print('hello!');"),
              d.file('goodbye.dart', "void main() => print('goodbye!');"),
              d.file('shell.sh', 'echo shell'),
              d.dir('subdir', [
                d.file('sub.dart', "void main() => print('sub!');"),
              ]),
            ]),
          ],
        )
        ..serve('bar', '1.2.3', deps: {'foo': '1.2.3'});

      await d.appDir(dependencies: {'foo': '1.2.3'}).create();

      await pubGet(
        args: ['--precompile'],
        output: allOf([
          contains('Built foo:hello.'),
          contains('Built foo:goodbye.'),
        ]),
      );

      await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
        d.dir('foo', [
          d.file('hello.dart-$versionSuffix.snapshot', contains('hello!')),
          d.file('goodbye.dart-$versionSuffix.snapshot', contains('goodbye!')),
          d.nothing('shell.sh-$versionSuffix.snapshot'),
          d.nothing('subdir'),
        ]),
      ]).validate();

      var process = await pubRun(args: ['foo:hello']);
      expect(process.stdout, emits('hello!'));
      await process.shouldExit();

      process = await pubRun(args: ['foo:goodbye']);
      expect(process.stdout, emits('goodbye!'));
      await process.shouldExit();
    });

    group('again if', () {
      test('its package is updated', () async {
        final server = await servePackages();
        server.serve(
          'foo',
          '1.2.3',
          contents: [
            d.dir('bin', [
              d.file('hello.dart', "void main() => print('hello!');"),
            ]),
          ],
        );

        await d.appDir(dependencies: {'foo': 'any'}).create();

        await pubGet(
          args: ['--precompile'],
          output: contains('Built foo:hello.'),
        );

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
          d.file('hello.dart-$versionSuffix.snapshot', contains('hello!')),
        ]).validate();

        server.serve(
          'foo',
          '1.2.4',
          contents: [
            d.dir('bin', [
              d.file('hello.dart', "void main() => print('hello 2!');"),
            ]),
          ],
        );

        await pubUpgrade(
          args: ['--precompile'],
          output: contains('Built foo:hello.'),
        );

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
          d.file('hello.dart-$versionSuffix.snapshot', contains('hello 2!')),
        ]).validate();

        final process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits('hello 2!'));
        await process.shouldExit();
      });

      test('a dependency of its package is updated', () async {
        final server = await servePackages();

        server.serve(
          'foo',
          '1.2.3',
          pubspec: {
            'dependencies': {'bar': 'any'},
          },
          contents: [
            d.dir('bin', [
              d.file('hello.dart', """
            import 'package:bar/bar.dart';

            void main() => print(message);
          """),
            ]),
          ],
        );
        server.serve(
          'bar',
          '1.2.3',
          contents: [
            d.dir('lib', [d.file('bar.dart', "final message = 'hello!';")]),
          ],
        );

        await d.appDir(dependencies: {'foo': 'any'}).create();

        await pubGet(
          args: ['--precompile'],
          output: contains('Built foo:hello.'),
        );

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
          d.file('hello.dart-$versionSuffix.snapshot', contains('hello!')),
        ]).validate();

        server.serve(
          'bar',
          '1.2.4',
          contents: [
            d.dir('lib', [d.file('bar.dart', "final message = 'hello 2!';")]),
          ],
        );

        await pubUpgrade(
          args: ['--precompile'],
          output: contains('Built foo:hello.'),
        );

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
          d.file('hello.dart-$versionSuffix.snapshot', contains('hello 2!')),
        ]).validate();

        final process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits('hello 2!'));
        await process.shouldExit();
      });

      test('a git dependency of its package is updated', () async {
        ensureGit();

        await d.git('foo.git', [
          d.pubspec({'name': 'foo', 'version': '0.0.1'}),
          d.dir('bin', [
            d.file('hello.dart', "void main() => print('Hello!');"),
          ]),
        ]).create();

        await d
            .appDir(
              dependencies: {
                'foo': {'git': '../foo.git'},
              },
            )
            .create();

        await pubGet(
          args: ['--precompile'],
          output: contains('Built foo:hello.'),
        );

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
          d.file('hello.dart-$versionSuffix.snapshot', contains('Hello!')),
        ]).validate();

        await d.git('foo.git', [
          d.dir('bin', [
            d.file('hello.dart', "void main() => print('Goodbye!');"),
          ]),
        ]).commit();

        await pubUpgrade(
          args: ['--precompile'],
          output: contains('Built foo:hello.'),
        );

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin', 'foo'), [
          d.file('hello.dart-$versionSuffix.snapshot', contains('Goodbye!')),
        ]).validate();

        final process = await pubRun(args: ['foo:hello']);
        expect(process.stdout, emits('Goodbye!'));
        await process.shouldExit();
      });

      test('the SDK is out of date', () async {
        final server = await servePackages();
        server.serve(
          'foo',
          '5.6.7',
          contents: [
            d.dir('bin', [
              d.file('hello.dart', "void main() => print('hello!');"),
            ]),
          ],
        );

        await d.appDir(dependencies: {'foo': '5.6.7'}).create();

        await pubGet(args: ['--no-precompile']);

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
          d.dir('foo', [
            d.outOfDateSnapshot('hello.dart-$versionSuffix.snapshot'),
          ]),
        ]).create();

        final process = await pubRun(args: ['foo:hello']);

        // In the real world this would just print "hello!", but since we
        // collect all output we see the precompilation messages as well.
        expect(process.stdout, emits('Building package executable...'));
        expect(process.stdout, emitsThrough('hello!'));
        await process.shouldExit();

        await d.dir(p.join(appPath, '.dart_tool', 'pub', 'bin'), [
          d.dir('foo', [
            d.file('hello.dart-$versionSuffix.snapshot', contains('hello!')),
          ]),
        ]).validate();
      });
    });
  });
}
