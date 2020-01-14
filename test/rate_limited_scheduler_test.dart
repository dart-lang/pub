// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';
import 'package:pedantic/pedantic.dart';
import 'package:pub/src/rate_limited_scheduler.dart';

void main() {
  Map<String, Completer> threeCompleters() =>
      {'a': Completer(), 'b': Completer(), 'c': Completer()};

  test('scheduler is rate limited', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final scheduler = RateLimitedScheduler(f, maxConcurrentOperations: 2);
    await scheduler.withPrescheduling((preschedule) async {
      preschedule('a');
      preschedule('b');
      preschedule('c');
      await Future.wait(
          [isBeingProcessed['a'].future, isBeingProcessed['b'].future]);
      expect(isBeingProcessed['c'].isCompleted, isFalse);
      completers['a'].complete();
      await isBeingProcessed['c'].future;
      completers['c'].complete();
      expect(await scheduler.schedule('c'), 'C');
    });
  });

  test('scheduler.preschedule cancels unrun prescheduled task after callback',
      () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final scheduler = RateLimitedScheduler(f, maxConcurrentOperations: 1);

    await scheduler.withPrescheduling((preschedule1) async {
      await scheduler.withPrescheduling((preschedule2) async {
        preschedule1('a');
        preschedule2('b');
        preschedule1('c');
        await isBeingProcessed['a'].future;
        // b, c should not start processing due to rate-limiting.
        expect(isBeingProcessed['b'].isCompleted, isFalse);
        expect(isBeingProcessed['c'].isCompleted, isFalse);
      });
      completers['a'].complete();
      // b is removed from the queue, now c should start processing.
      await isBeingProcessed['c'].future;
      completers['c'].complete();
      expect(await scheduler.schedule('c'), 'C');
      // b is not on the queue anymore.
      expect(isBeingProcessed['b'].isCompleted, isFalse);
    });
  });

  test('scheduler.preschedule does not cancel tasks that are scheduled',
      () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final scheduler = RateLimitedScheduler(f, maxConcurrentOperations: 1);

    Future b;
    await scheduler.withPrescheduling((preschedule) async {
      preschedule('a');
      preschedule('b');
      await isBeingProcessed['a'].future;
      // b should not start processing due to rate-limiting.
      expect(isBeingProcessed['b'].isCompleted, isFalse);
      b = scheduler.schedule('b');
    });
    completers['a'].complete();
    expect(await scheduler.schedule('a'), 'A');
    // b was scheduled, so it should get processed now
    await isBeingProcessed['b'].future;
    completers['b'].complete();
    expect(await b, 'B');
  });

  test('scheduler caches results', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final scheduler = RateLimitedScheduler(f, maxConcurrentOperations: 2);

    completers['a'].complete();
    expect(await scheduler.schedule('a'), 'A');
    // Would fail if isBeingProcessed['a'] was completed twice
    expect(await scheduler.schedule('a'), 'A');
  });

  test('scheduler prioritizes fetched tasks before prefetched', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final scheduler = RateLimitedScheduler(f, maxConcurrentOperations: 1);
    await scheduler.withPrescheduling((preschedule) async {
      preschedule('a');
      preschedule('b');
      await isBeingProcessed['a'].future;
      final cResult = scheduler.schedule('c');
      expect(isBeingProcessed['b'].isCompleted, isFalse);
      completers['a'].complete();
      completers['c'].complete();
      await isBeingProcessed['c'].future;
      // 'c' is done before we allow 'b' to finish processing
      expect(await cResult, 'C');
    });
  });

  test('Errors trigger when the scheduled future is listened to', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return i.toUpperCase();
    }

    final scheduler = RateLimitedScheduler(f, maxConcurrentOperations: 2);

    await scheduler.withPrescheduling((preschedule) async {
      preschedule('a');
      preschedule('b');
      preschedule('c');
      await isBeingProcessed['a'].future;
      await isBeingProcessed['b'].future;
      expect(isBeingProcessed['c'].isCompleted, isFalse);
      unawaited(completers['c'].future.catchError((_) {}));
      completers['c'].completeError('errorC');
      completers['a'].completeError('errorA');
      await isBeingProcessed['c'].future;
      completers['b'].completeError('errorB');
      expect(() async => await scheduler.schedule('a'), throwsA('errorA'));
      expect(() async => await scheduler.schedule('b'), throwsA('errorB'));
      expect(() async => await scheduler.schedule('c'), throwsA('errorC'));
    });
  });

  test('tasks run in the zone they where enqueued in', () async {
    final completers = threeCompleters();
    final isBeingProcessed = threeCompleters();

    Future<String> f(String i) async {
      isBeingProcessed[i].complete();
      await completers[i].future;
      return Zone.current['zoneValue'];
    }

    final scheduler = RateLimitedScheduler(f, maxConcurrentOperations: 2);
    await scheduler.withPrescheduling((preschedule) async {
      runZoned(() {
        preschedule('a');
      }, zoneValues: {'zoneValue': 'A'});
      runZoned(() {
        preschedule('b');
      }, zoneValues: {'zoneValue': 'B'});
      runZoned(() {
        preschedule('c');
      }, zoneValues: {'zoneValue': 'C'});

      await runZoned(() async {
        await isBeingProcessed['a'].future;
        await isBeingProcessed['b'].future;
        // This will put 'c' in front of the queue, but in a zone with zoneValue
        // bound to S.
        final f = expectLater(scheduler.schedule('c'), completion('S'));
        completers['a'].complete();
        completers['b'].complete();
        expect(await scheduler.schedule('a'), 'A');
        expect(await scheduler.schedule('b'), 'B');
        completers['c'].complete();
        await f;
      }, zoneValues: {'zoneValue': 'S'});
    });
  });
}
