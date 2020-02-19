// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:pool/pool.dart';
import 'package:pedantic/pedantic.dart';

/// Handles rate-limited scheduling of tasks.
///
/// Tasks are identified by a jobId of type [J] (should be useful as a Hash-key)
/// and run with a supplied async function.
///
/// Designed to allow speculatively running tasks that will likely be needed
/// later with [withPrescheduling].
///
/// Errors thrown by tasks scheduled with the `preschedule` callback will only
/// be triggered when you await the [Future] returned by [schedule].
///
/// The operation will run in the [Zone] that the task was in when enqueued.
///
/// If a task if [preschedule]d and later [schedule]d before the operation is
/// started, the task will go in front of the queue with the zone of the
/// [schedule] operation.
///
/// Example:
///
/// ```dart
/// // A scheduler that, given a uri, gets that page and returns the body
/// final scheduler = RateLimitedScheduler(http.read);
///
/// scheduler.withPresceduling((preschedule) {
///   // Start fetching `pub.dev` and `dart.dev` in the background.
///   scheduler.preschedule(Uri.parse('https://pub.dev/'));
///   scheduler.preschedule(Uri.parse('https://dart.dev/'));
///   // ... do time-consuming task.
///   // Now we actually need `pub.dev`.
///   final pubDevBody =
///       await scheduler.schedule(Uri.parse('https://pub.dev/'));
///   // if the `dart.dev` task has not started yet, it will be canceled when
///   // leaving `withPresceduling`.
/// });
/// ```
class RateLimitedScheduler<J, V> {
  final Future<V> Function(J) _runJob;

  /// The results of ongoing and finished jobs.
  final Map<J, Completer<V>> _cache = <J, Completer<V>>{};

  /// Tasks that are waiting to be run.
  final Queue<_Task<J>> _queue = Queue<_Task<J>>();

  /// Rate limits the number of concurrent jobs.
  final Pool _pool;

  /// Jobs that have started running.
  final Set<J> _started = {};

  RateLimitedScheduler(Future<V> Function(J) runJob,
      {maxConcurrentOperations = 10})
      : _runJob = runJob,
        _pool = Pool(maxConcurrentOperations);

  /// Pick the next task in [_queue] and run it.
  ///
  /// If the task is already in [_started] it will not be run again.
  Future<void> _processNextTask() async {
    if (_queue.isEmpty) {
      return;
    }
    final task = _queue.removeFirst();
    final completer = _cache[task.jobId];

    if (!_started.add(task.jobId)) {
      return;
    }

    // Use an async function to catch sync exceptions from _runJob.
    Future<V> runJob() async {
      return await task.zone.runUnary(_runJob, task.jobId);
    }

    completer.complete(runJob());
    // Listen to errors on the completer:
    // this will make errors thrown by [_run] not
    // become uncaught.
    //
    // They will still show up for other listeners of the future.
    await completer.future.catchError((_) {});
  }

  /// Calls [callback] with a function that can pre-schedule jobs.
  ///
  /// When [callback] returns, all jobs that where prescheduled by [callback]
  /// that have not started running will be removed from the work queue
  /// (if they have been added separately by [schedule] they will still be
  /// executed).
  Future<R> withPrescheduling<R>(
    FutureOr<R> Function(void Function(J) preschedule) callback,
  ) async {
    final prescheduled = <_Task>{};
    try {
      return await callback((jobId) {
        if (_started.contains(jobId)) return;
        final task = _Task(jobId, Zone.current);
        _cache.putIfAbsent(jobId, () => Completer());
        _queue.addLast(task);
        prescheduled.add(task);

        unawaited(_pool.withResource(_processNextTask));
      });
    } finally {
      _queue.removeWhere(prescheduled.contains);
    }
  }

  /// Returns a future that completed with the result of running [jobId].
  ///
  /// If [jobId] has already run, the cached result will be returned.
  /// If [jobId] is not yet running, it will go to the front of the work queue
  /// to be scheduled next when there are free resources.
  Future<V> schedule(J jobId) {
    final completer = _cache.putIfAbsent(jobId, () => Completer());
    if (!_started.contains(jobId)) {
      final task = _Task(jobId, Zone.current);
      _queue.addFirst(task);
      scheduleMicrotask(() => _pool.withResource(_processNextTask));
    }
    return completer.future;
  }
}

class _Task<J> {
  final J jobId;
  final Zone zone;
  _Task(this.jobId, this.zone);

  @override
  String toString() => jobId.toString();
}
