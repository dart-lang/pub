// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import "dart:collection";

import "package:pool/pool.dart";

/// Handles rate-limited scheduling of tasks.
///
/// Tasks are named with a key of type [J] (should be useful as a Hash-key) and
/// run with a supplied asynch function.
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

  /// True when the processing loop is running.
  bool _isRunning = false;

  RateLimitedScheduler(Future<V> Function(J) runJob,
      {maxConcurrentOperations = 10})
      : _runJob = runJob,
        _pool = Pool(maxConcurrentOperations);

  /// Starts running operations from the queue. Taking the first items first.
  void _process() async {
    if (_isRunning) return;
    _isRunning = true;
    while (_queue.isNotEmpty) {
      final resource = await _pool.request();
      if (_queue.isEmpty) {
        resource.release();
        break;
      }
      final task = _queue.removeFirst();
      final completer = _cache[task.jobId];
      if (completer.isCompleted || _started.contains(task)) {
        resource.release();
        continue;
      }

      _started.add(task.jobId);
      Future<V> runJob() async {
        try {
          return await task.zone.runUnary(_runJob, task.jobId);
        } finally {
          resource.release();
        }
      }

      completer.complete(runJob());
    }
    _isRunning = false;
  }

  /// Calls [callback] with a function that can pre-schedule jobs.
  ///
  /// When [callback] returns, all jobs that where prescheduled by [callback]
  /// that have not started running will be removed from the work queue
  /// (if they have been added seperately by [schedule] they will still be
  /// executed).
  Future<R> withPrescheduling<R>(
    FutureOr<R> Function(void Function(J) preschedule) callback,
  ) async {
    final prescheduled = <_Task>{};
    try {
      return await callback((jobId) {
        final task = _Task(jobId, Zone.current);
        prescheduled.add(task);
        _queue.addLast(task);
        _cache.putIfAbsent(
            jobId,
            () => Completer()
              // Listen to errors: this will make errors thrown by [_run] not
              // become uncaught.
              // They will still show up for other listeners of the future.
              ..future.catchError((error) {}));
        _process();
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
    if (!completer.isCompleted) {
      // We allow adding the same jobId twice to the queue.
      // It will get dedupped by the [_process] loop.
      _queue.addFirst(_Task(jobId, Zone.current));
      _process();
    }
    return completer.future;
  }
}

class _Task<J> {
  final J jobId;
  final Zone zone;
  _Task(this.jobId, this.zone);

  toString() => jobId.toString();
}
