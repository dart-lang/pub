// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS d.file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:barback/barback.dart';
import 'package:pub/src/compiler.dart';
import 'package:pub/src/entrypoint.dart';
import 'package:pub/src/barback/asset_environment.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/system_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import '../descriptor.dart' as d;
import '../test_pub.dart';
import 'utils.dart';

main() {
  String libFilePath;

  setUp(() async {
    await d.dir(appPath, [
      d.appPubspec(),
      d.dir("lib", [
        d.file("lib.dart", "foo() => 'foo';"),
      ])
    ]).create();

    await pubGet();
    libFilePath = p.join(d.sandbox, appPath, "lib", "lib.dart");
  });

  test("setting a long build-delay works", () async {
    var pubServeProcess =
        await pubServe(forcePoll: false, args: ['--build-delay', '1000']);
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'foo';");

    writeTextFile(libFilePath, "foo() => 'bar';");
    await new Future.delayed(new Duration(milliseconds: 500));
    writeTextFile(libFilePath, "foo() => 'baz';");

    // Should only see one build.
    expect(pubServeProcess.stdout,
        emitsThrough(contains('Build completed successfully')));
    expect(pubServeProcess.stdout, neverEmits('Build completed successfully'));

    await requestShouldSucceed("packages/myapp/lib.dart", "foo() => 'baz';");

    await endPubServe();
  });

  group('unit tests', () {
    Barback barback;
    List<BuildResult> barbackResults;
    AssetEnvironment environment;
    final libAssetId = new AssetId('myapp', 'lib/lib.dart');
    // Watcher for the lib dir.
    _MockDirectoryWatcher libWatcher;
    _MockWatcherType watcherType;

    setUp(() async {
      var entrypoint =
          new Entrypoint(p.join(d.sandbox, appPath), new SystemCache());
      watcherType = new _MockWatcherType();
      environment = await AssetEnvironment.create(entrypoint, BarbackMode.DEBUG,
          watcherType: watcherType,
          buildDelay: new Duration(milliseconds: 50),
          compiler: Compiler.none);
      barback = environment.barback;
      libWatcher = watcherType.watchers[p.join(d.sandbox, appPath, 'lib')];
      // Collect build results.
      barbackResults = <BuildResult>[];
      barback.results.listen(barbackResults.add);
    });

    tearDown(() async {
      await environment.cleanUp();
    });

    // Attempts to wait for all pending barback builds.
    Future waitForBarback() async {
      // First, wait for the next build to complete.
      await barback.results.first;
      // Then wait for all assets, which should capture additional builds if
      // they occur.
      await barback.getAllAssets();
      // Give the stream a chance to deliver a new build if one did occur.
      await new Future(() {});
    }

    test("continual fast edits don't cause multiple builds", () async {
      expect(await (await barback.getAssetById(libAssetId)).readAsString(),
          "foo() => 'foo';");

      for (var i = 0; i < 10; i++) {
        writeTextFile(libFilePath, "foo() => '$i';");
        libWatcher.addEvent(new WatchEvent(ChangeType.MODIFY, libFilePath));
        await new Future.delayed(new Duration(milliseconds: 10));
      }

      // Should get exactly one build result.
      await waitForBarback();
      expect(barbackResults.length, 1);
      expect(await (await barback.getAssetById(libAssetId)).readAsString(),
          "foo() => '9';");
    });

    // Regression test for https://github.com/dart-lang/sdk/issues/29890
    test("editors safe write features shouldn't cause failed builds", () async {
      // Simulate the safe-write feature from many editors:
      //   - Create a backup file
      //   - Edit original file
      //   - Delete backup file
      var backupFilePath = p.join(d.sandbox, appPath, "lib", "lib.dart.bak");
      writeTextFile(backupFilePath, "foo() => 'foo';");
      libWatcher.addEvent(new WatchEvent(ChangeType.ADD, backupFilePath));
      await new Future(() {});
      deleteEntry(backupFilePath);
      libWatcher.addEvent(new WatchEvent(ChangeType.REMOVE, backupFilePath));

      // Should get a single successful build result.
      await waitForBarback();
      expect(barbackResults.length, 1);
      expect(barbackResults.first.succeeded, isTrue);
    });
  });
}

/// Mock [WatcherType] that creates [_MockDirectoryWatcher]s and gives you
/// access to them.
class _MockWatcherType implements WatcherType {
  final watchers = <String, _MockDirectoryWatcher>{};

  _MockDirectoryWatcher create(String dir) {
    var watcher = new _MockDirectoryWatcher(dir);
    watchers[dir] = watcher;
    return watcher;
  }
}

/// Mock [DirectoryWatcher] that you add events to manually using [addEvent].
class _MockDirectoryWatcher implements DirectoryWatcher {
  final _eventsController = new StreamController<WatchEvent>();
  Stream<WatchEvent> get events => _eventsController.stream;

  final String path;
  String get directory => path;

  final ready = new Future<Null>(() {});
  bool get isReady => true;

  _MockDirectoryWatcher(this.path);

  void addEvent(WatchEvent event) => _eventsController.add(event);
}
