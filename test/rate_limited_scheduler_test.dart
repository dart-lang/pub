// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:pub/src/rate_limited_scheduler.dart';

main() {
  threeCompleters() => {'a': Completer(), 'b': Completer(), 'c': Completer()};

  test('Retriever is rate limited', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final retriever = RateLimitedScheduler(
        (input, _) => CancelableOperation.fromFuture(f(input)),
        maxConcurrentOperations: 2);

    retriever.prefetch('a');
    retriever.prefetch('b');
    retriever.prefetch('c');
    await Future.wait(
        [isBeingProcessed['a'].future, isBeingProcessed['b'].future]);
    expect(isBeingProcessed['c'].isCompleted, isFalse);
    completers['a'].complete();
    await isBeingProcessed['c'].future;
    completers['c'].complete();
    expect(await retriever.fetch('c'), 'C');
  });

  test('Retriever.stop cancels active task', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();
    final canceled = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await Future.any([canceled[i].future, completers[i].future]);
      return i.toUpperCase();
    }

    final retriever = RateLimitedScheduler(
        (input, _) => CancelableOperation.fromFuture(f(input),
            onCancel: () => canceled[input].complete()),
        maxConcurrentOperations: 2);

    retriever.prefetch('a');
    retriever.prefetch('b');
    retriever.prefetch('c');
    await Future.wait(
        [isBeingProcessed['a'].future, isBeingProcessed['b'].future]);
    retriever.stop();
    await Future.wait([canceled['a'].future, canceled['b'].future]);
    // c should never start processing due to rate-limiting.
    expect(isBeingProcessed['c'].isCompleted, isFalse);
  });

  test('Retriever caches results', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final retriever = RateLimitedScheduler(
        (input, _) => CancelableOperation.fromFuture(f(input)),
        maxConcurrentOperations: 2);

    completers['a'].complete();
    expect(await retriever.fetch('a'), 'A');
    // Would fail if isBeingProcessed['a'] was completed twice
    expect(await retriever.fetch('a'), 'A');
  });

  test('Retriever prioritizes fetched tasks before prefetched', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final retriever = RateLimitedScheduler(
        (input, _) => CancelableOperation.fromFuture(f(input)),
        maxConcurrentOperations: 1);

    retriever.prefetch('a');
    retriever.prefetch('b');
    await isBeingProcessed['a'].future;
    final cResult = retriever.fetch('c');
    expect(isBeingProcessed['b'].isCompleted, isFalse);
    completers['a'].complete();
    completers['c'].complete();
    await isBeingProcessed['c'].future;
    // 'c' is done before we allow 'b' to finish processing
    expect(await cResult, 'C');
  });

  test('Errors trigger when the fetched future is listened to', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final retriever = RateLimitedScheduler(
        (input, _) => CancelableOperation.fromFuture(f(input)),
        maxConcurrentOperations: 2);

    retriever.prefetch('a');
    retriever.prefetch('b');
    retriever.prefetch('c');
    await isBeingProcessed['a'].future;
    await isBeingProcessed['b'].future;
    expect(isBeingProcessed['c'].isCompleted, isFalse);
    completers['c'].future.catchError((_) {});
    completers['c'].completeError('errorC');
    completers['a'].completeError('errorA');
    await isBeingProcessed['c'].future;
    completers['b'].completeError('errorB');
    expect(() async => await retriever.fetch('a'), throwsA('errorA'));
    expect(() async => await retriever.fetch('b'), throwsA('errorB'));
    expect(() async => await retriever.fetch('c'), throwsA('errorC'));
  });

  test('tasks run in the zone they where enqueued in', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return Zone.current['zoneValue'];
    }

    final retriever = RateLimitedScheduler(
        (input, _) => CancelableOperation.fromFuture(f(input)),
        maxConcurrentOperations: 2);

    runZoned(() {
      retriever.prefetch('a');
    }, zoneValues: {'zoneValue': 'A'});
    runZoned(() {
      retriever.prefetch('b');
    }, zoneValues: {'zoneValue': 'B'});
    runZoned(() {
      retriever.prefetch('c');
    }, zoneValues: {'zoneValue': 'C'});

    await runZoned(() async {
      await isBeingProcessed['a'].future;
      await isBeingProcessed['b'].future;
      // This will put 'c' in front of the queue, but in a zone with zoneValue
      // bound to S.
      final f = expectLater(retriever.fetch('c'), completion('S'));
      completers['a'].complete();
      completers['b'].complete();
      expect(await retriever.fetch('a'), 'A');
      expect(await retriever.fetch('b'), 'B');
      completers['c'].complete();
      await f;
    }, zoneValues: {'zoneValue': 'S'});
  });
}
