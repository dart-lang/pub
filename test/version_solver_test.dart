// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/lock_file.dart';
import 'package:pub/src/pubspec.dart';
import 'package:pub/src/source/hosted.dart';
import 'package:pub/src/system_cache.dart';
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

void main() {
  group('basic graph', basicGraph);
  group('with lockfile', withLockFile);
  group('root dependency', rootDependency);
  group('dev dependency', devDependency);
  group('unsolvable', unsolvable);
  group('bad source', badSource);
  group('backtracking', backtracking);
  group('Dart SDK constraint', dartSdkConstraint);
  group('SDK constraint', sdkConstraint);
  group('pre-release', prerelease);
  group('override', override);
  group('downgrade', downgrade);
  group('regressions', regressions);
}

void basicGraph() {
  test('no dependencies', () async {
    await d.appDir().create();
    await expectResolves(result: {});
  });

  test('simple dependency tree', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'aa': '1.0.0', 'ab': '1.0.0'})
      ..serve('aa', '1.0.0')
      ..serve('ab', '1.0.0')
      ..serve('b', '1.0.0', deps: {'ba': '1.0.0', 'bb': '1.0.0'})
      ..serve('ba', '1.0.0')
      ..serve('bb', '1.0.0');

    await d.appDir(dependencies: {'a': '1.0.0', 'b': '1.0.0'}).create();
    await expectResolves(
      result: {
        'a': '1.0.0',
        'aa': '1.0.0',
        'ab': '1.0.0',
        'b': '1.0.0',
        'ba': '1.0.0',
        'bb': '1.0.0'
      },
    );
  });

  test('shared dependency with overlapping constraints', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'shared': '>=2.0.0 <4.0.0'})
      ..serve('b', '1.0.0', deps: {'shared': '>=3.0.0 <5.0.0'})
      ..serve('shared', '2.0.0')
      ..serve('shared', '3.0.0')
      ..serve('shared', '3.6.9')
      ..serve('shared', '4.0.0')
      ..serve('shared', '5.0.0');

    await d.appDir(dependencies: {'a': '1.0.0', 'b': '1.0.0'}).create();
    await expectResolves(
      result: {'a': '1.0.0', 'b': '1.0.0', 'shared': '3.6.9'},
    );
  });

  test(
      'shared dependency where dependent version in turn affects other '
      'dependencies', () async {
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '1.0.1', deps: {'bang': '1.0.0'})
      ..serve('foo', '1.0.2', deps: {'whoop': '1.0.0'})
      ..serve('foo', '1.0.3', deps: {'zoop': '1.0.0'})
      ..serve('bar', '1.0.0', deps: {'foo': '<=1.0.1'})
      ..serve('bang', '1.0.0')
      ..serve('whoop', '1.0.0')
      ..serve('zoop', '1.0.0');

    await d.appDir(dependencies: {'foo': '<=1.0.2', 'bar': '1.0.0'}).create();
    await expectResolves(
      result: {'foo': '1.0.1', 'bar': '1.0.0', 'bang': '1.0.0'},
    );
  });

  test('circular dependency', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('bar', '1.0.0', deps: {'foo': '1.0.0'});

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'});
  });

  test('removed dependency', () async {
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0')
      ..serve('bar', '1.0.0')
      ..serve('bar', '2.0.0', deps: {'baz': '1.0.0'})
      ..serve('baz', '1.0.0', deps: {'foo': '2.0.0'});

    await d.appDir(dependencies: {'foo': '1.0.0', 'bar': 'any'}).create();
    await expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'}, tries: 2);
  });
}

void withLockFile() {
  test('with compatible locked dependency', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('foo', '1.0.1', deps: {'bar': '1.0.1'})
      ..serve('foo', '1.0.2', deps: {'bar': '1.0.2'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '1.0.1')
      ..serve('bar', '1.0.2');

    await d.appDir(dependencies: {'foo': '1.0.1'}).create();
    await expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});
  });

  test('with incompatible locked dependency', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('foo', '1.0.1', deps: {'bar': '1.0.1'})
      ..serve('foo', '1.0.2', deps: {'bar': '1.0.2'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '1.0.1')
      ..serve('bar', '1.0.2');

    await d.appDir(dependencies: {'foo': '1.0.1'}).create();
    await expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});

    await d.appDir(dependencies: {'foo': '>1.0.1'}).create();
    await expectResolves(result: {'foo': '1.0.2', 'bar': '1.0.2'});
  });

  test('with unrelated locked dependency', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('foo', '1.0.1', deps: {'bar': '1.0.1'})
      ..serve('foo', '1.0.2', deps: {'bar': '1.0.2'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '1.0.1')
      ..serve('bar', '1.0.2')
      ..serve('baz', '1.0.0');

    await d.appDir(dependencies: {'baz': '1.0.0'}).create();
    await expectResolves(result: {'baz': '1.0.0'});

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(result: {'foo': '1.0.2', 'bar': '1.0.2'});
  });

  test(
      'unlocks dependencies if necessary to ensure that a new '
      'dependency is satisfied', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '<2.0.0'})
      ..serve('bar', '1.0.0', deps: {'baz': '<2.0.0'})
      ..serve('baz', '1.0.0', deps: {'qux': '<2.0.0'})
      ..serve('qux', '1.0.0')
      ..serve('foo', '2.0.0', deps: {'bar': '<3.0.0'})
      ..serve('bar', '2.0.0', deps: {'baz': '<3.0.0'})
      ..serve('baz', '2.0.0', deps: {'qux': '<3.0.0'})
      ..serve('qux', '2.0.0')
      ..serve('newdep', '2.0.0', deps: {'baz': '>=1.5.0'});

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await expectResolves(
      result: {'foo': '1.0.0', 'bar': '1.0.0', 'baz': '1.0.0', 'qux': '1.0.0'},
    );

    await d.appDir(dependencies: {'foo': 'any', 'newdep': '2.0.0'}).create();
    await expectResolves(
      result: {
        'foo': '2.0.0',
        'bar': '2.0.0',
        'baz': '2.0.0',
        'qux': '1.0.0',
        'newdep': '2.0.0'
      },
      tries: 2,
    );
  });

  // Issue 1853
  test(
      "produces a nice message for a locked dependency that's the only "
      'version of its package', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '>=2.0.0'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '2.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(result: {'foo': '1.0.0', 'bar': '2.0.0'});

    await d.appDir(dependencies: {'foo': 'any', 'bar': '<2.0.0'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because myapp depends on foo any which depends on bar >=2.0.0,
        bar >=2.0.0 is required.
      So, because myapp depends on bar <2.0.0, version solving failed.
    '''),
    );
  });
}

void rootDependency() {
  test('with root source', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'myapp': 'any'});

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await expectResolves(result: {'foo': '1.0.0'});
  });

  test('with mismatched sources', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'myapp': 'any'})
      ..serve(
        'bar',
        '1.0.0',
        deps: {
          'myapp': {'git': 'http://nowhere.com/'}
        },
      );

    await d.appDir(dependencies: {'foo': '1.0.0', 'bar': '1.0.0'}).create();
    await expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'});
  });

  test('with wrong version', () async {
    final server = await servePackages();
    server.serve('foo', '1.0.0', deps: {'myapp': '>0.0.0'});

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because myapp depends on foo 1.0.0 which depends on myapp >0.0.0,
        myapp >0.0.0 is required.
      So, because myapp is 0.0.0, version solving failed.
    '''),
    );
  });
}

void devDependency() {
  test("includes root package's dev dependencies", () async {
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('bar', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.0.0', 'bar': '1.0.0'}
      })
    ]).create();

    await expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'});
  });

  test("includes dev dependency's transitive dependencies", () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('bar', '1.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {'foo': '1.0.0'}
      })
    ]).create();

    await expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'});
  });

  test("ignores transitive dependency's dev dependencies", () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'dev_dependencies': {'bar': '1.0.0'}
      },
    );

    await d.appDir(dependencies: {'foo': '1.0.0'}).create();
    await expectResolves(result: {'foo': '1.0.0'});
  });

  group('with both a dev and regular dependency', () {
    test('succeeds when both are satisfied', () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0')
        ..serve('foo', '3.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '>=1.0.0 <3.0.0'},
          'dev_dependencies': {'foo': '>=2.0.0 <4.0.0'}
        })
      ]).create();

      await expectResolves(result: {'foo': '2.0.0'});
    });

    test("fails when main dependency isn't satisfied", () async {
      final server = await servePackages();
      server.serve('foo', '3.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '>=1.0.0 <3.0.0'},
          'dev_dependencies': {'foo': '>=2.0.0 <4.0.0'}
        })
      ]).create();

      await expectResolves(
        error: equalsIgnoringWhitespace('''
        Because no versions of foo match ^2.0.0 and myapp depends on foo
          >=1.0.0 <3.0.0, foo ^1.0.0 is required.
        So, because myapp depends on foo >=2.0.0 <4.0.0, version solving failed.
      '''),
      );
    });

    test("fails when dev dependency isn't satisfied", () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '>=1.0.0 <3.0.0'},
          'dev_dependencies': {'foo': '>=2.0.0 <4.0.0'}
        })
      ]).create();

      await expectResolves(
        error: equalsIgnoringWhitespace('''
        Because no versions of foo match ^2.0.0 and myapp depends on foo
          >=1.0.0 <3.0.0, foo ^1.0.0 is required.
        So, because myapp depends on foo >=2.0.0 <4.0.0, version solving failed.
      '''),
      );
    });

    test('fails when dev and main constraints are incompatible', () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '>=1.0.0 <2.0.0'},
          'dev_dependencies': {'foo': '>=2.0.0 <3.0.0'}
        })
      ]).create();

      await expectResolves(
        error: equalsIgnoringWhitespace('''
        Because myapp depends on both foo ^1.0.0 and foo ^2.0.0, version
          solving failed.
      '''),
      );
    });

    test('fails when dev and main sources are incompatible', () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {'foo': '>=1.0.0 <2.0.0'},
          'dev_dependencies': {
            'foo': {'path': '../foo'}
          }
        })
      ]).create();

      await expectResolves(
        error: equalsIgnoringWhitespace('''
        Because myapp depends on both foo from hosted and foo from path, version
          solving failed.
      '''),
      );
    });

    test('fails when dev and main descriptions are incompatible', () async {
      final server = await servePackages();
      server.serve('foo', '1.0.0');

      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'dependencies': {
            'foo': {'path': 'foo'}
          },
          'dev_dependencies': {
            'foo': {'path': '../foo'}
          }
        })
      ]).create();

      await expectResolves(
        error: equalsIgnoringWhitespace('''
      Because myapp depends on both foo from path foo and foo from path
          ..${Platform.pathSeparator}foo, version solving failed.
      '''),
      );
    });
  });
}

void unsolvable() {
  test('no version that matches constraint', () async {
    await servePackages()
      ..serve('foo', '2.0.0')
      ..serve('foo', '2.1.3');

    await d.appDir(dependencies: {'foo': '>=1.0.0 <2.0.0'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace("""
      Because myapp depends on foo ^1.0.0 which doesn't match any versions,
        version solving failed.
    """),
    );
  });

  test('no version that matches combined constraint', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'shared': '>=2.0.0 <3.0.0'})
      ..serve('bar', '1.0.0', deps: {'shared': '>=2.9.0 <4.0.0'})
      ..serve('shared', '2.5.0')
      ..serve('shared', '3.5.0');

    await d.appDir(dependencies: {'foo': '1.0.0', 'bar': '1.0.0'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because every version of foo depends on shared ^2.0.0 and no versions of
        shared match ^2.9.0, every version of foo requires
        shared >=2.0.0 <2.9.0.
      And because every version of bar depends on shared >=2.9.0 <4.0.0, bar is
        incompatible with foo.
      So, because myapp depends on both foo 1.0.0 and bar 1.0.0, version
        solving failed.
    '''),
    );
  });

  test('disjoint constraints', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'shared': '<=2.0.0'})
      ..serve('bar', '1.0.0', deps: {'shared': '>3.0.0'})
      ..serve('shared', '2.0.0')
      ..serve('shared', '4.0.0');

    await d.appDir(dependencies: {'foo': '1.0.0', 'bar': '1.0.0'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because every version of bar depends on shared >3.0.0 and every version
        of foo depends on shared <=2.0.0, bar is incompatible with foo.
      So, because myapp depends on both foo 1.0.0 and bar 1.0.0, version
        solving failed.
    '''),
    );
  });

  test('mismatched descriptions', () async {
    var otherServer = await startPackageServer();
    otherServer.serve('shared', '1.0.0');

    await servePackages()
      ..serve('foo', '1.0.0', deps: {'shared': '1.0.0'})
      ..serve(
        'bar',
        '1.0.0',
        deps: {
          'shared': {
            'hosted': {'name': 'shared', 'url': otherServer.url},
            'version': '1.0.0'
          }
        },
      )
      ..serve('shared', '1.0.0');

    await d.appDir(dependencies: {'foo': '1.0.0', 'bar': '1.0.0'}).create();

    await expectResolves(
      error: allOf([
        contains(
            'Because every version of bar depends on shared from hosted on '
            'http://localhost:'),
        contains(' and every version of foo depends on shared from hosted on '
            'http://localhost:'),
        contains(', bar is incompatible with foo.'),
        contains('So, because myapp depends on both foo 1.0.0 and bar 1.0.0, '
            'version solving failed.')
      ]),
    );
  });

  test('mismatched sources', () async {
    await d.dir('shared', [d.libPubspec('shared', '1.0.0')]).create();

    await servePackages()
      ..serve('foo', '1.0.0', deps: {'shared': '1.0.0'})
      ..serve(
        'bar',
        '1.0.0',
        deps: {
          'shared': {'path': p.join(d.sandbox, 'shared')}
        },
      )
      ..serve('shared', '1.0.0');

    await d.appDir(dependencies: {'foo': '1.0.0', 'bar': '1.0.0'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because every version of bar depends on shared from path and every
        version of foo depends on shared from hosted, bar is incompatible with
        foo.
      So, because myapp depends on both foo 1.0.0 and bar 1.0.0, version
        solving failed.
    '''),
    );
  });

  test('no valid solution', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'b': '1.0.0'})
      ..serve('a', '2.0.0', deps: {'b': '2.0.0'})
      ..serve('b', '1.0.0', deps: {'a': '2.0.0'})
      ..serve('b', '2.0.0', deps: {'a': '1.0.0'});

    await d.appDir(dependencies: {'a': 'any', 'b': 'any'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because b <2.0.0 depends on a 2.0.0 which depends on b 2.0.0, b <2.0.0 is
        forbidden.
      Because b >=2.0.0 depends on a 1.0.0 which depends on b 1.0.0, b >=2.0.0
        is forbidden.
      Thus, b is forbidden.
      So, because myapp depends on b any, version solving failed.
    '''),
      tries: 2,
    );
  });

  // This is a regression test for #15550.
  test('no version that matches while backtracking', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('b', '1.0.0');

    await d.appDir(dependencies: {'a': 'any', 'b': '>1.0.0'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace("""
      Because myapp depends on b >1.0.0 which doesn't match any versions,
        version solving failed.
    """),
    );
  });

  // This is a regression test for #18300.
  test('issue 18300', () async {
    await servePackages()
      ..serve('analyzer', '0.12.2')
      ..serve(
        'angular',
        '0.10.0',
        deps: {'di': '>=0.0.32 <0.1.0', 'collection': '>=0.9.1 <1.0.0'},
      )
      ..serve(
        'angular',
        '0.9.11',
        deps: {'di': '>=0.0.32 <0.1.0', 'collection': '>=0.9.1 <1.0.0'},
      )
      ..serve(
        'angular',
        '0.9.10',
        deps: {'di': '>=0.0.32 <0.1.0', 'collection': '>=0.9.1 <1.0.0'},
      )
      ..serve('collection', '0.9.0')
      ..serve('collection', '0.9.1')
      ..serve('di', '0.0.37', deps: {'analyzer': '>=0.13.0 <0.14.0'})
      ..serve('di', '0.0.36', deps: {'analyzer': '>=0.13.0 <0.14.0'});

    await d
        .appDir(dependencies: {'angular': 'any', 'collection': 'any'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because every version of angular depends on di ^0.0.32 which depends on
        analyzer ^0.13.0, every version of angular requires analyzer ^0.13.0.
      So, because no versions of analyzer match ^0.13.0 and myapp depends on
        angular any, version solving failed.
    '''),
    );
  });
}

void badSource() {
  test('fail if the root package has a bad source in dep', () async {
    await d.appDir(
      dependencies: {
        'foo': {'bad': 'any'}
      },
    ).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because myapp depends on foo from unknown source "bad", version solving
        failed.
    '''),
    );
  });

  test('fail if the root package has a bad source in dev dep', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dev_dependencies': {
          'foo': {'bad': 'any'}
        }
      })
    ]).create();

    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because myapp depends on foo from unknown source "bad", version solving
        failed.
    '''),
    );
  });

  test('fail if all versions have bad source in dep', () async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
        deps: {
          'bar': {'bad': 'any'}
        },
      )
      ..serve(
        'foo',
        '1.0.1',
        deps: {
          'baz': {'bad': 'any'}
        },
      )
      ..serve(
        'foo',
        '1.0.2',
        deps: {
          'bang': {'bad': 'any'}
        },
      );

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because foo <1.0.1 depends on bar from unknown source "bad", foo <1.0.1 is
        forbidden.
      And because foo >=1.0.1 <1.0.2 depends on baz from bad, foo <1.0.2
        requires baz from bad.
      And because baz comes from unknown source "bad" and foo >=1.0.2 depends on
        bang from bad, every version of foo requires bang from bad.
      So, because bang comes from unknown source "bad" and myapp depends on foo any,
        version solving failed.
    '''),
      tries: 3,
    );
  });

  test('ignore versions with bad source in dep', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': 'any'})
      ..serve(
        'foo',
        '1.0.1',
        deps: {
          'bar': {'bad': 'any'}
        },
      )
      ..serve(
        'foo',
        '1.0.2',
        deps: {
          'bar': {'bad': 'any'}
        },
      )
      ..serve('bar', '1.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(result: {'foo': '1.0.0', 'bar': '1.0.0'}, tries: 2);
  });

  // Issue 1853
  test('reports a nice error across a collapsed cause', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': 'any'})
      ..serve('bar', '1.0.0', deps: {'baz': 'any'})
      ..serve('baz', '1.0.0');
    await d.dir('baz', [d.libPubspec('baz', '1.0.0')]).create();

    await d.appDir(
      dependencies: {
        'foo': 'any',
        'baz': {'path': '../baz'}
      },
    ).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because every version of foo depends on bar any which depends on baz any,
        every version of foo requires baz from hosted.
      So, because myapp depends on both foo any and baz from path, version
        solving failed.
    '''),
    );
  });
}

void backtracking() {
  test('circular dependency on older version', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '2.0.0', deps: {'b': '1.0.0'})
      ..serve('b', '1.0.0', deps: {'a': '1.0.0'});

    await d.appDir(dependencies: {'a': '>=1.0.0'}).create();
    await expectResolves(result: {'a': '1.0.0'}, tries: 2);
  });

  test('diamond dependency graph', () async {
    await servePackages()
      ..serve('a', '2.0.0', deps: {'c': '^1.0.0'})
      ..serve('a', '1.0.0')
      ..serve('b', '2.0.0', deps: {'c': '^3.0.0'})
      ..serve('b', '1.0.0', deps: {'c': '^2.0.0'})
      ..serve('c', '3.0.0')
      ..serve('c', '2.0.0')
      ..serve('c', '1.0.0');

    await d.appDir(dependencies: {'a': 'any', 'b': 'any'}).create();
    await expectResolves(result: {'a': '1.0.0', 'b': '2.0.0', 'c': '3.0.0'});
  });

  // c 2.0.0 is incompatible with y 2.0.0 because it requires x 1.0.0, but that
  // requirement only exists because of both a and b. The solver should be able
  // to deduce c 2.0.0's incompatibility and select c 1.0.0 instead.
  test('backjumps after a partial satisfier', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'x': '>=1.0.0'})
      ..serve('b', '1.0.0', deps: {'x': '<2.0.0'})
      ..serve('c', '1.0.0')
      ..serve('c', '2.0.0', deps: {'a': 'any', 'b': 'any'})
      ..serve('x', '0.0.0')
      ..serve('x', '1.0.0', deps: {'y': '1.0.0'})
      ..serve('x', '2.0.0')
      ..serve('y', '1.0.0')
      ..serve('y', '2.0.0');

    await d.appDir(dependencies: {'c': 'any', 'y': '^2.0.0'}).create();
    await expectResolves(result: {'c': '1.0.0', 'y': '2.0.0'}, tries: 2);
  });

  // This matches the Branching Error Reporting example in the version solver
  // documentation, and tests that we display line numbers correctly.
  test('branching error reporting', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'a': '^1.0.0', 'b': '^1.0.0'})
      ..serve('foo', '1.1.0', deps: {'x': '^1.0.0', 'y': '^1.0.0'})
      ..serve('a', '1.0.0', deps: {'b': '^2.0.0'})
      ..serve('b', '1.0.0')
      ..serve('b', '2.0.0')
      ..serve('x', '1.0.0', deps: {'y': '^2.0.0'})
      ..serve('y', '1.0.0')
      ..serve('y', '2.0.0');

    await d.appDir(dependencies: {'foo': '^1.0.0'}).create();
    await expectResolves(
      // We avoid equalsIgnoringWhitespace() here because we want to test the
      // formatting of the line number.
      error: '    Because foo <1.1.0 depends on a ^1.0.0 which depends on b '
          '^2.0.0, foo <1.1.0 requires b ^2.0.0.\n'
          '(1) So, because foo <1.1.0 depends on b ^1.0.0, foo <1.1.0 is '
          'forbidden.\n'
          '\n'
          '    Because foo >=1.1.0 depends on x ^1.0.0 which depends on y '
          '^2.0.0, foo >=1.1.0 requires y ^2.0.0.\n'
          '    And because foo >=1.1.0 depends on y ^1.0.0, foo >=1.1.0 is '
          'forbidden.\n'
          '    And because foo <1.1.0 is forbidden (1), foo is forbidden.\n'
          '    So, because myapp depends on foo ^1.0.0, version solving '
          'failed.',
      tries: 2,
    );
  });

  // The latest versions of a and b disagree on c. An older version of either
  // will resolve the problem. This test validates that b, which is farther
  // in the dependency graph from myapp is downgraded first.
  test('rolls back leaf versions first', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'b': 'any'})
      ..serve('a', '2.0.0', deps: {'b': 'any', 'c': '2.0.0'})
      ..serve('b', '1.0.0')
      ..serve('b', '2.0.0', deps: {'c': '1.0.0'})
      ..serve('c', '1.0.0')
      ..serve('c', '2.0.0');

    await d.appDir(dependencies: {'a': 'any'}).create();
    await expectResolves(result: {'a': '2.0.0', 'b': '1.0.0', 'c': '2.0.0'});
  });

  // Only one version of baz, so foo and bar will have to downgrade until they
  // reach it.
  test('simple transitive', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('foo', '2.0.0', deps: {'bar': '2.0.0'})
      ..serve('foo', '3.0.0', deps: {'bar': '3.0.0'})
      ..serve('bar', '1.0.0', deps: {'baz': 'any'})
      ..serve('bar', '2.0.0', deps: {'baz': '2.0.0'})
      ..serve('bar', '3.0.0', deps: {'baz': '3.0.0'})
      ..serve('baz', '1.0.0');

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(
      result: {'foo': '1.0.0', 'bar': '1.0.0', 'baz': '1.0.0'},
      tries: 3,
    );
  });

  // This ensures it doesn't exhaustively search all versions of b when it's
  // a-2.0.0 whose dependency on c-2.0.0-nonexistent led to the problem. We
  // make sure b has more versions than a so that the solver tries a first
  // since it sorts sibling dependencies by number of versions.
  test('backjump to nearer unsatisfied package', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'c': '1.0.0'})
      ..serve('a', '2.0.0', deps: {'c': '2.0.0-nonexistent'})
      ..serve('b', '1.0.0')
      ..serve('b', '2.0.0')
      ..serve('b', '3.0.0')
      ..serve('c', '1.0.0');

    await d.appDir(dependencies: {'a': 'any', 'b': 'any'}).create();
    await expectResolves(
      result: {'a': '1.0.0', 'b': '3.0.0', 'c': '1.0.0'},
      tries: 2,
    );
  });

  // Tests that the backjumper will jump past unrelated selections when a
  // source conflict occurs. This test selects, in order:
  // - myapp -> a
  // - myapp -> b
  // - myapp -> c (1 of 5)
  // - b -> a
  // It selects a and b first because they have fewer versions than c. It
  // traverses b's dependency on a after selecting a version of c because
  // dependencies are traversed breadth-first (all of myapps's immediate deps
  // before any other their deps).
  //
  // This means it doesn't discover the source conflict until after selecting
  // c. When that happens, it should backjump past c instead of trying older
  // versions of it since they aren't related to the conflict.
  test('successful backjump to conflicting source', () async {
    await d.dir('a', [d.libPubspec('a', '1.0.0')]).create();

    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('b', '1.0.0', deps: {'a': 'any'})
      ..serve(
        'b',
        '2.0.0',
        deps: {
          'a': {'path': p.join(d.sandbox, 'a')}
        },
      )
      ..serve('c', '1.0.0')
      ..serve('c', '2.0.0')
      ..serve('c', '3.0.0')
      ..serve('c', '4.0.0')
      ..serve('c', '5.0.0');

    await d.appDir(dependencies: {'a': 'any', 'b': 'any', 'c': 'any'}).create();
    await expectResolves(result: {'a': '1.0.0', 'b': '1.0.0', 'c': '5.0.0'});
  });

  // Like the above test, but for a conflicting description.
  test('successful backjump to conflicting description', () async {
    var otherServer = await startPackageServer();
    otherServer.serve('a', '1.0.0');

    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('b', '1.0.0', deps: {'a': 'any'})
      ..serve(
        'b',
        '2.0.0',
        deps: {
          'a': {
            'hosted': {'name': 'a', 'url': otherServer.url}
          }
        },
      )
      ..serve('c', '1.0.0')
      ..serve('c', '2.0.0')
      ..serve('c', '3.0.0')
      ..serve('c', '4.0.0')
      ..serve('c', '5.0.0');

    await d.appDir(dependencies: {'a': 'any', 'b': 'any', 'c': 'any'}).create();
    await expectResolves(result: {'a': '1.0.0', 'b': '1.0.0', 'c': '5.0.0'});
  });

  // Similar to the above two tests but where there is no solution. It should
  // fail in this case with no backtracking.
  test('failing backjump to conflicting source', () async {
    await d.dir('a', [d.libPubspec('a', '1.0.0')]).create();

    await servePackages()
      ..serve('a', '1.0.0')
      ..serve(
        'b',
        '1.0.0',
        deps: {
          'a': {'path': p.join(d.sandbox, 'shared')}
        },
      )
      ..serve('c', '1.0.0')
      ..serve('c', '2.0.0')
      ..serve('c', '3.0.0')
      ..serve('c', '4.0.0')
      ..serve('c', '5.0.0');

    await d.appDir(dependencies: {'a': 'any', 'b': 'any', 'c': 'any'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      Because every version of b depends on a from path and myapp depends on
        a from hosted, b is forbidden.
      So, because myapp depends on b any, version solving failed.
    '''),
    );
  });

  test('failing backjump to conflicting description', () async {
    var otherServer = await startPackageServer();
    otherServer.serve('a', '1.0.0');

    await servePackages()
      ..serve('a', '1.0.0')
      ..serve(
        'b',
        '1.0.0',
        deps: {
          'a': {
            'hosted': {'name': 'a', 'url': otherServer.url}
          }
        },
      )
      ..serve('c', '1.0.0')
      ..serve('c', '2.0.0')
      ..serve('c', '3.0.0')
      ..serve('c', '4.0.0')
      ..serve('c', '5.0.0');

    await d.appDir(dependencies: {'a': 'any', 'b': 'any', 'c': 'any'}).create();
    await expectResolves(
      error: allOf([
        contains('Because every version of b depends on a from hosted on '
            'http://localhost:'),
        contains(' and myapp depends on a from hosted on http://localhost:'),
        contains(', b is forbidden.'),
        contains('So, because myapp depends on b any, version solving failed.')
      ]),
    );
  });

  // Dependencies are ordered so that packages with fewer versions are tried
  // first. Here, there are two valid solutions (either a or b must be
  // downgraded once). The chosen one depends on which dep is traversed first.
  // Since b has fewer versions, it will be traversed first, which means a will
  // come later. Since later selections are revised first, a gets downgraded.
  test('traverse into package with fewer versions first', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'c': 'any'})
      ..serve('a', '2.0.0', deps: {'c': 'any'})
      ..serve('a', '3.0.0', deps: {'c': 'any'})
      ..serve('a', '4.0.0', deps: {'c': 'any'})
      ..serve('a', '5.0.0', deps: {'c': '1.0.0'})
      ..serve('b', '1.0.0', deps: {'c': 'any'})
      ..serve('b', '2.0.0', deps: {'c': 'any'})
      ..serve('b', '3.0.0', deps: {'c': 'any'})
      ..serve('b', '4.0.0', deps: {'c': '2.0.0'})
      ..serve('c', '1.0.0')
      ..serve('c', '2.0.0');

    await d.appDir(dependencies: {'a': 'any', 'b': 'any'}).create();
    await expectResolves(result: {'a': '4.0.0', 'b': '4.0.0', 'c': '2.0.0'});
  });

  test('complex backtrack', () async {
    final server = await servePackages();
    // This sets up a hundred versions of foo and bar, 0.0.0 through 9.9.0. Each
    // version of foo depends on a baz with the same major version. Each version
    // of bar depends on a baz with the same minor version. There is only one
    // version of baz, 0.0.0, so only older versions of foo and bar will
    // satisfy it.
    server.serve('baz', '0.0.0');
    for (var i = 0; i < 10; i++) {
      for (var j = 0; j < 10; j++) {
        server.serve('foo', '$i.$j.0', deps: {'baz': '$i.0.0'});
        server.serve('bar', '$i.$j.0', deps: {'baz': '0.$j.0'});
      }
    }

    await d.appDir(dependencies: {'foo': 'any', 'bar': 'any'}).create();
    await expectResolves(
      result: {'foo': '0.9.0', 'bar': '9.0.0', 'baz': '0.0.0'},
      tries: 10,
    );
  });

  // If there's a disjoint constraint on a package, then selecting other
  // versions of it is a waste of time: no possible versions can match. We need
  // to jump past it to the most recent package that affected the constraint.
  test('backjump past failed package on disjoint constraint', () async {
    await servePackages()
      ..serve(
        'a',
        '1.0.0',
        deps: {
          'foo': 'any' // ok
        },
      )
      ..serve(
        'a',
        '2.0.0',
        deps: {
          'foo': '<1.0.0' // disjoint with myapp's constraint on foo
        },
      )
      ..serve('foo', '2.0.0')
      ..serve('foo', '2.0.1')
      ..serve('foo', '2.0.2')
      ..serve('foo', '2.0.3')
      ..serve('foo', '2.0.4');

    await d.appDir(dependencies: {'a': 'any', 'foo': '>2.0.0'}).create();
    await expectResolves(result: {'a': '1.0.0', 'foo': '2.0.4'});
  });

  // This is a regression test for #18666. It was possible for the solver to
  // "forget" that a package had previously led to an error. In that case, it
  // would backtrack over the failed package instead of trying different
  // versions of it.
  test('finds solution with less strict constraint', () async {
    await servePackages()
      ..serve('a', '2.0.0')
      ..serve('a', '1.0.0')
      ..serve('b', '1.0.0', deps: {'a': '1.0.0'})
      ..serve('c', '1.0.0', deps: {'b': 'any'})
      ..serve('d', '2.0.0', deps: {'myapp': 'any'})
      ..serve('d', '1.0.0', deps: {'myapp': '<1.0.0'});

    await d.appDir(dependencies: {'a': 'any', 'c': 'any', 'd': 'any'}).create();
    await expectResolves(
      result: {'a': '1.0.0', 'b': '1.0.0', 'c': '1.0.0', 'd': '2.0.0'},
    );
  });
}

void dartSdkConstraint() {
  test('root matches SDK', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '3.1.2+3'}
      })
    ]).create();

    await expectResolves(result: {});
  });

  test('root does not match SDK', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'sdk': '2.12.0'}
      })
    ]).create();

    await expectResolves(
      error: equalsIgnoringWhitespace('''
      The current Dart SDK version is 3.1.2+3.

      Because myapp requires SDK version 2.12.0, version solving failed.
    '''),
    );
  });

  test('dependency does not match SDK', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '1.0.0',
      pubspec: {
        'environment': {'sdk': '2.12.0'}
      },
    );

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      The current Dart SDK version is 3.1.2+3.

      Because myapp depends on foo any which requires SDK version 2.12.0, version
        solving failed.
    '''),
    );
  });

  test('transitive dependency does not match SDK', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': 'any'})
      ..serve(
        'bar',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '2.12.0'}
        },
      );

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(
      error: equalsIgnoringWhitespace('''
      The current Dart SDK version is 3.1.2+3.

      Because every version of foo depends on bar any which requires SDK version
        2.12.0, foo is forbidden.
      So, because myapp depends on foo any, version solving failed.
    '''),
    );
  });

  test('selects a dependency version that allows the SDK', () async {
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '3.1.2+3'}
        },
      )
      ..serve(
        'foo',
        '2.0.0',
        pubspec: {
          'environment': {'sdk': '3.1.2+3'}
        },
      )
      ..serve(
        'foo',
        '3.0.0',
        pubspec: {
          'environment': {'sdk': '0.0.0'}
        },
      )
      ..serve(
        'foo',
        '4.0.0',
        pubspec: {
          'environment': {'sdk': '0.0.0'}
        },
      );

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(result: {'foo': '2.0.0'});
  });

  test('selects a transitive dependency version that allows the SDK', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': 'any'})
      ..serve(
        'bar',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '3.1.2+3'}
        },
      )
      ..serve(
        'bar',
        '2.0.0',
        pubspec: {
          'environment': {'sdk': '3.1.2+3'}
        },
      )
      ..serve(
        'bar',
        '3.0.0',
        pubspec: {
          'environment': {'sdk': '0.0.0'}
        },
      )
      ..serve(
        'bar',
        '4.0.0',
        pubspec: {
          'environment': {'sdk': '0.0.0'}
        },
      );

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(result: {'foo': '1.0.0', 'bar': '2.0.0'});
  });

  test(
      'selects a dependency version that allows a transitive '
      'dependency that allows the SDK', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('foo', '2.0.0', deps: {'bar': '2.0.0'})
      ..serve('foo', '3.0.0', deps: {'bar': '3.0.0'})
      ..serve('foo', '4.0.0', deps: {'bar': '4.0.0'})
      ..serve(
        'bar',
        '1.0.0',
        pubspec: {
          'environment': {'sdk': '3.1.2+3'}
        },
      )
      ..serve(
        'bar',
        '2.0.0',
        pubspec: {
          'environment': {'sdk': '3.1.2+3'}
        },
      )
      ..serve(
        'bar',
        '3.0.0',
        pubspec: {
          'environment': {'sdk': '0.0.0'}
        },
      )
      ..serve(
        'bar',
        '4.0.0',
        pubspec: {
          'environment': {'sdk': '0.0.0'}
        },
      );

    await d.appDir(dependencies: {'foo': 'any'}).create();
    await expectResolves(result: {'foo': '2.0.0', 'bar': '2.0.0'}, tries: 2);
  });
}

void sdkConstraint() {
  group('without a Flutter SDK', () {
    test('fails for the root package', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'flutter': '1.2.3'}
        })
      ]).create();

      await expectResolves(
        error: equalsIgnoringWhitespace('''
        Because myapp requires the Flutter SDK, version solving failed.

        Flutter users should run `flutter pub get` instead of `dart pub get`.
      '''),
      );
    });

    test('fails for a dependency', () async {
      final server = await servePackages();
      server.serve(
        'foo',
        '1.0.0',
        pubspec: {
          'environment': {'flutter': 'any', 'sdk': defaultSdkConstraint}
        },
      );

      await d.appDir(dependencies: {'foo': 'any'}).create();
      await expectResolves(
        error: equalsIgnoringWhitespace('''
        Because myapp depends on foo any which requires the Flutter SDK, version
          solving failed.

        Flutter users should run `flutter pub get` instead of `dart pub get`.
      '''),
      );
    });

    test("chooses a version that doesn't need Flutter", () async {
      await servePackages()
        ..serve('foo', '1.0.0')
        ..serve('foo', '2.0.0')
        ..serve(
          'foo',
          '3.0.0',
          pubspec: {
            'environment': {'flutter': '0.0.0'}
          },
        );

      await d.appDir(dependencies: {'foo': 'any'}).create();
      await expectResolves(result: {'foo': '2.0.0'});
    });

    test('fails even with a matching Dart SDK constraint', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'sdk': '3.1.2+3', 'flutter': '1.2.3'}
        })
      ]).create();

      await expectResolves(
        error: equalsIgnoringWhitespace('''
        Because myapp requires the Flutter SDK, version solving failed.

        Flutter users should run `flutter pub get` instead of `dart pub get`.
      '''),
      );
    });
  });

  test('without a Fuchsia SDK fails for the root package', () async {
    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'environment': {'fuchsia': '1.2.3'}
      })
    ]).create();

    await expectResolves(
      error: equalsIgnoringWhitespace('''
        Because myapp requires the Fuchsia SDK, version solving failed.

        Please set the FUCHSIA_DART_SDK_ROOT environment variable to point to
          the root of the Fuchsia SDK for Dart.
      '''),
    );
  });

  group('with a Flutter SDK', () {
    setUp(() {
      return d.dir('flutter', [d.file('version', '1.2.3')]).create();
    });

    test('succeeds with a matching constraint', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'flutter': 'any'}
        })
      ]).create();

      await expectResolves(
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        result: {},
      );
    });

    test('fails with a non-matching constraint', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'flutter': '>1.2.3'}
        })
      ]).create();

      await expectResolves(
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        error: equalsIgnoringWhitespace('''
            The current Flutter SDK version is 1.2.3.

            Because myapp requires Flutter SDK version >1.2.3, version solving
              failed.
          '''),
      );
    });

    test('succeeds if both Flutter and Dart SDKs match', () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'sdk': '3.1.2+3', 'flutter': '1.2.3'}
        })
      ]).create();

      await expectResolves(
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        result: {},
      );
    });

    test("fails if Flutter SDK doesn't match but Dart does", () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {'sdk': '3.1.2+3', 'flutter': '>1.2.3'}
        })
      ]).create();

      await expectResolves(
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        error: equalsIgnoringWhitespace('''
            The current Flutter SDK version is 1.2.3.

            Because myapp requires Flutter SDK version >1.2.3, version solving
              failed.
          '''),
      );
    });

    test("fails if Dart SDK doesn't match but Flutter does", () async {
      await d.dir(appPath, [
        d.pubspec({
          'name': 'myapp',
          'environment': {
            'sdk': '>3.1.2+3',
            'flutter': '1.2.3',
          },
        }),
      ]).create();

      await expectResolves(
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        error: equalsIgnoringWhitespace('''
            The current Dart SDK version is 3.1.2+3.

            Because myapp requires SDK version >3.1.2+3, version solving
            failed.
          '''),
      );
    });

    test('selects the latest dependency with a matching constraint', () async {
      await servePackages()
        ..serve(
          'foo',
          '1.0.0',
          pubspec: {
            'environment': {'flutter': '^0.0.0', 'sdk': defaultSdkConstraint}
          },
        )
        ..serve(
          'foo',
          '2.0.0',
          pubspec: {
            'environment': {'flutter': '^1.0.0', 'sdk': defaultSdkConstraint}
          },
        )
        ..serve(
          'foo',
          '3.0.0',
          pubspec: {
            'environment': {'flutter': '^2.0.0', 'sdk': defaultSdkConstraint}
          },
        );

      await d.appDir(dependencies: {'foo': 'any'}).create();
      await expectResolves(
        environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
        result: {'foo': '2.0.0'},
      );
    });
  });
}

void prerelease() {
  test('prefer stable versions over unstable', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '1.1.0-dev')
      ..serve('a', '2.0.0-dev')
      ..serve('a', '3.0.0-dev');

    await d.appDir(dependencies: {'a': 'any'}).create();
    await expectResolves(result: {'a': '1.0.0'});
  });

  test('use latest allowed prerelease if no stable versions match', () async {
    await servePackages()
      ..serve('a', '1.0.0-dev')
      ..serve('a', '1.1.0-dev')
      ..serve('a', '1.9.0-dev')
      ..serve('a', '3.0.0');

    await d.appDir(dependencies: {'a': '<2.0.0'}).create();
    await expectResolves(result: {'a': '1.9.0-dev'});
  });

  test('use an earlier stable version on a < constraint', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '1.1.0')
      ..serve('a', '2.0.0-dev')
      ..serve('a', '2.0.0');

    await d.appDir(dependencies: {'a': '<2.0.0'}).create();
    await expectResolves(result: {'a': '1.1.0'});
  });

  test('prefer a stable version even if constraint mentions unstable',
      () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '1.1.0')
      ..serve('a', '2.0.0-dev')
      ..serve('a', '2.0.0');

    await d.appDir(dependencies: {'a': '<=2.0.0-dev'}).create();
    await expectResolves(result: {'a': '1.1.0'});
  });

  test('use pre-release when desired', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '1.1.0-dev');

    await d.appDir(dependencies: {'a': '^1.1.0-dev'}).create();
    await expectResolves(result: {'a': '1.1.0-dev'});
  });

  test('can upgrade from pre-release', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '1.1.0-dev')
      ..serve('a', '1.1.0');

    await d.appDir(dependencies: {'a': '^1.1.0-dev'}).create();
    await expectResolves(result: {'a': '1.1.0'});
  });

  test('will use pre-release if depended on in stable release', () async {
    // This behavior is desired because a stable package has dependency on a
    // pre-release.
    await servePackages()
      ..serve('a', '1.0.0', deps: {'b': '^1.0.0'})
      ..serve('a', '1.1.0', deps: {'b': '^1.1.0-dev'})
      ..serve('b', '1.0.0')
      ..serve('b', '1.1.0-dev');

    await d.appDir(dependencies: {'a': '^1.0.0'}).create();
    await expectResolves(
      result: {
        'a': '1.1.0',
        'b': '1.1.0-dev',
      },
    );
  });

  test('backtracks pre-release choice with direct dependency', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'b': '^1.0.0'})
      ..serve('a', '1.1.0', deps: {'b': '^1.1.0-dev'})
      ..serve('b', '1.0.0')
      ..serve('b', '1.1.0-dev');

    await d.appDir(
      dependencies: {
        'a': '^1.0.0',
        'b':
            '^1.0.0', // Direct dependency prevents us from using a pre-release.
      },
    ).create();
    await expectResolves(
      result: {
        'a': '1.0.0',
        'b': '1.0.0',
      },
    );
  });

  test('backtracking pre-release fails with indirect dependency', () async {
    // NOTE: This behavior is not necessarily desired.
    //       If feasible it might worth changing this behavior in the future.
    await servePackages()
      ..serve('a', '1.0.0', deps: {'b': '^1.0.0'})
      ..serve('a', '1.1.0', deps: {'b': '^1.1.0-dev'})
      ..serve('b', '1.0.0')
      ..serve('b', '1.1.0-dev')
      ..serve('c', '1.0.0', deps: {'b': '^1.0.0'});

    await d.appDir(
      dependencies: {
        'a': '^1.0.0',
        'c': '^1.0.0', // This doesn't not prevent using a pre-release.
      },
    ).create();
    await expectResolves(
      result: {
        'a': '1.1.0',
        'b': '1.1.0-dev',
        'c': '1.0.0',
      },
    );
  });

  test('https://github.com/dart-lang/pub/issues/3057 regression', () async {
    // This used to cause an infinite loop.
    await servePackages()
      ..serve('a', '0.12.0', deps: {})
      ..serve('b', '0.1.0', deps: {'c': '2.0.0'})
      ..serve('b', '0.9.0-1', deps: {'c': '^1.6.0'})
      ..serve('b', '0.10.0', deps: {'a': '1.0.0'})
      ..serve('b', '0.17.0', deps: {'a': '1.0.0'})
      ..serve('c', '2.0.1', deps: {});

    await d.appDir(
      dependencies: {
        'a': '0.12.0',
        'b': 'any',
      },
    ).create();
    await expectResolves(
      error: contains(
        'So, because myapp depends on both a 0.12.0 and b any, version solving failed.',
      ),
      tries: 2,
    );
  });

  test('https://github.com/dart-lang/pub/pull/3038 regression', () async {
    await servePackages()
      ..serve('a', '1.1.0', deps: {'b': '^1.0.0'})
      ..serve('b', '1.0.0', deps: {'c': '^1.0.0'})
      ..serve('c', '0.9.0')
      ..serve('b', '1.1.0-alpha')
      ..serve('a', '1.0.0', deps: {'b': '^1.1.0-alpha'});

    await d.appDir(
      dependencies: {
        'a': '^1.0.0',
      },
    ).create();
    await expectResolves(tries: 2);
  });
}

void override() {
  test('chooses best version matching override constraint', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '2.0.0')
      ..serve('a', '3.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'a': 'any'},
        'dependency_overrides': {'a': '<3.0.0'}
      })
    ]).create();

    await expectResolves(result: {'a': '2.0.0'});
  });

  test('uses override as dependency', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '2.0.0')
      ..serve('a', '3.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'a': '<3.0.0'}
      })
    ]).create();

    await expectResolves(result: {'a': '2.0.0'});
  });

  test('ignores other constraints on overridden package', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '2.0.0')
      ..serve('a', '3.0.0')
      ..serve('b', '1.0.0', deps: {'a': '1.0.0'})
      ..serve('c', '1.0.0', deps: {'a': '3.0.0'});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'b': 'any', 'c': 'any'},
        'dependency_overrides': {'a': '2.0.0'}
      })
    ]).create();

    await expectResolves(result: {'a': '2.0.0', 'b': '1.0.0', 'c': '1.0.0'});
  });

  test('backtracks on overidden package for its constraints', () async {
    await servePackages()
      ..serve('a', '1.0.0', deps: {'shared': 'any'})
      ..serve('a', '2.0.0', deps: {'shared': '1.0.0'})
      ..serve('shared', '1.0.0')
      ..serve('shared', '2.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'shared': '2.0.0'},
        'dependency_overrides': {'a': '<3.0.0'}
      })
    ]).create();

    await expectResolves(result: {'a': '1.0.0', 'shared': '2.0.0'});
  });

  test('override compatible with locked dependency', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('foo', '1.0.1', deps: {'bar': '1.0.1'})
      ..serve('foo', '1.0.2', deps: {'bar': '1.0.2'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '1.0.1')
      ..serve('bar', '1.0.2');

    await d.appDir(dependencies: {'foo': '1.0.1'}).create();
    await expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'foo': '<1.0.2'}
      })
    ]).create();

    await expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});
  });

  test('override incompatible with locked dependency', () async {
    await servePackages()
      ..serve('foo', '1.0.0', deps: {'bar': '1.0.0'})
      ..serve('foo', '1.0.1', deps: {'bar': '1.0.1'})
      ..serve('foo', '1.0.2', deps: {'bar': '1.0.2'})
      ..serve('bar', '1.0.0')
      ..serve('bar', '1.0.1')
      ..serve('bar', '1.0.2');

    await d.appDir(dependencies: {'foo': '1.0.1'}).create();
    await expectResolves(result: {'foo': '1.0.1', 'bar': '1.0.1'});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'foo': '>1.0.1'}
      })
    ]).create();

    await expectResolves(result: {'foo': '1.0.2', 'bar': '1.0.2'});
  });

  test('no version that matches override', () async {
    await servePackages()
      ..serve('foo', '2.0.0')
      ..serve('foo', '2.1.3');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'foo': '>=1.0.0 <2.0.0'}
      })
    ]).create();

    await expectResolves(
      error: equalsIgnoringWhitespace("""
      Because myapp depends on foo ^1.0.0 which doesn't match any versions,
        version solving failed.
    """),
    );
  });

  test('overrides a bad source without error', () async {
    final server = await servePackages();
    server.serve('foo', '0.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {
          'foo': {'bad': 'any'}
        },
        'dependency_overrides': {'foo': 'any'}
      })
    ]).create();

    await expectResolves(result: {'foo': '0.0.0'});
  });

  test('overrides an unmatched SDK constraint', () async {
    final server = await servePackages();
    server.serve(
      'foo',
      '0.0.0',
      pubspec: {
        'environment': {'sdk': '0.0.0'}
      },
    );

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependency_overrides': {'foo': 'any'}
      })
    ]).create();

    await expectResolves(result: {'foo': '0.0.0'});
  });

  test('overrides an unmatched root dependency', () async {
    final server = await servePackages();
    server.serve('foo', '0.0.0', deps: {'myapp': '1.0.0'});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'version': '2.0.0',
        'dependency_overrides': {'foo': 'any'}
      })
    ]).create();

    await expectResolves(result: {'foo': '0.0.0'});
  });

  // Regression test for #1853
  test("overrides a locked package's dependency", () async {
    await servePackages()
      ..serve('foo', '1.2.3', deps: {'bar': '1.2.3'})
      ..serve('bar', '1.2.3')
      ..serve('bar', '0.0.1');

    await d.appDir(dependencies: {'foo': 'any'}).create();

    await expectResolves(result: {'foo': '1.2.3', 'bar': '1.2.3'});

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'foo': 'any'},
        'dependency_overrides': {'bar': '0.0.1'}
      })
    ]).create();

    await expectResolves(result: {'foo': '1.2.3', 'bar': '0.0.1'});
  });

  test('overrides in pubspec_overrides.yaml', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '2.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'a': '1.0.0'},
      }),
      d.pubspecOverrides({
        'dependency_overrides': {'a': '2.0.0'}
      }),
    ]).create();

    await expectResolves(result: {'a': '2.0.0'});
  });

  test('pubspec_overrides.yaml takes precedence over pubspec.yaml', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '2.0.0')
      ..serve('a', '3.0.0');

    await d.dir(appPath, [
      d.pubspec({
        'name': 'myapp',
        'dependencies': {'a': '1.0.0'},
        'dependency_overrides': {'a': '2.0.0'}
      }),
      d.pubspecOverrides({
        'dependency_overrides': {'a': '3.0.0'}
      }),
    ]).create();

    await expectResolves(result: {'a': '3.0.0'});
  });
}

void downgrade() {
  test('downgrades a dependency to the lowest matching version', () async {
    await servePackages()
      ..serve('foo', '1.0.0')
      ..serve('foo', '2.0.0-dev')
      ..serve('foo', '2.0.0')
      ..serve('foo', '2.1.0');

    await d.appDir(dependencies: {'foo': '2.1.0'}).create();
    await expectResolves(result: {'foo': '2.1.0'});

    await d.appDir(dependencies: {'foo': '>=2.0.0 <3.0.0'}).create();
    await expectResolves(result: {'foo': '2.0.0'}, downgrade: true);
  });

  test(
      'use earliest allowed prerelease if no stable versions match '
      'while downgrading', () async {
    await servePackages()
      ..serve('a', '1.0.0')
      ..serve('a', '2.0.0-dev.1')
      ..serve('a', '2.0.0-dev.2')
      ..serve('a', '2.0.0-dev.3');

    await d.appDir(dependencies: {'a': '>=2.0.0-dev.1 <3.0.0'}).create();
    await expectResolves(result: {'a': '2.0.0-dev.1'}, downgrade: true);
  });
}

/// Runs "pub get" and makes assertions about its results.
///
/// If [result] is passed, it's parsed as a pubspec-style dependency map, and
/// this asserts that the resulting lockfile matches those dependencies, and
/// that it contains only packages listed in [result].
///
/// If [error] is passed, this asserts that pub's error output matches the
/// value. It may be a String, a [RegExp], or a [Matcher].
///
/// If [output] is passed, this asserts that the results match. It may be a
/// [String], a [RegExp], or a [Matcher].
///
/// Asserts that version solving looks at exactly [tries] solutions. It defaults
/// to allowing only a single solution.
///
/// If [environment] is passed, it's added to the OS environment when running
/// pub.
///
/// If [downgrade] is `true`, this runs "pub downgrade" instead of "pub get".
Future expectResolves({
  Map? result,
  error,
  output,
  int? tries,
  Map<String, String>? environment,
  bool downgrade = false,
}) async {
  await runPub(
    args: [downgrade ? 'downgrade' : 'get'],
    environment: environment,
    output: output ??
        (error == null
            ? anyOf(
                contains('Got dependencies!'),
                matches(RegExp(r'Changed \d+ dependenc(ies|y)!')),
              )
            : null),
    error: error,
    silent: contains('Tried ${tries ?? 1} solutions'),
    exitCode: error == null ? 0 : 1,
  );

  if (result == null) return;

  var cache = SystemCache();
  var registry = cache.sources;
  var lockFile =
      LockFile.load(p.join(d.sandbox, appPath, 'pubspec.lock'), registry);
  var resultPubspec = Pubspec.fromMap({'dependencies': result}, registry);

  var ids = Map.from(lockFile.packages);
  for (var dep in resultPubspec.dependencies.values) {
    expect(ids, contains(dep.name));
    var id = ids.remove(dep.name);
    final description = dep.description;
    if (description is HostedDescription &&
        (description.url == SystemCache().hosted.defaultUrl)) {
      // If the dep uses the default hosted source, grab it from the test
      // package server rather than pub.dev.
      dep = cache.hosted
          .refFor(dep.name, url: globalServer.url)
          .withConstraint(dep.constraint);
    }
    expect(dep.allows(id), isTrue, reason: 'Expected $id to match $dep.');
  }

  expect(ids, isEmpty, reason: 'Expected no additional packages.');
}

void regressions() {
  test('reformatRanges with a build', () async {
    await servePackages()
      ..serve(
        'integration_test',
        '1.0.1',
        deps: {'vm_service': '>= 4.2.0 <6.0.0'},
      )
      ..serve(
        'integration_test',
        '1.0.2+2',
        deps: {'vm_service': '>= 4.2.0 <7.0.0'},
      )
      ..serve('vm_service', '7.3.0');
    await d.appDir(dependencies: {'integration_test': '^1.0.2'}).create();
    await expectResolves(
      error: contains(
        'Because no versions of integration_test match >=1.0.2 <1.0.2+2',
      ),
    );
  });

  test('diamond sdk deps', () async {
    await d.dir('flutter', [
      d.dir('bin/cache/pkg', [
        d.dir(
          'baz',
          [d.libDir('baz', 'foo 0.0.1'), d.libPubspec('baz', '0.0.1')],
        )
      ]),
      d.file('version', '1.2.3')
    ]).create();
    await servePackages()
      ..serve(
        'foo',
        '1.0.0',
        deps: {
          'baz': {'sdk': 'flutter'}
        },
      )
      ..serve(
        'bar',
        '1.0.0',
        deps: {
          'baz': {'sdk': 'flutter'}
        },
      );
    await d.appDir(dependencies: {'foo': 'any', 'bar': 'any'}).create();
    await expectResolves(
      environment: {'FLUTTER_ROOT': p.join(d.sandbox, 'flutter')},
    );
  });
}
