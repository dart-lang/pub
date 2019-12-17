// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import "dart:collection";

import "package:pool/pool.dart";
import "package:async/async.dart";

/// Handles rate-limited scheduling of tasks.
///
/// Tasks are named with a key of type [K] (should be useful as a Hash-key) and
/// run with a supplied function producing a CancelableOperation.
///
/// Designed to allow prefetching of tasks that will likely be needed
/// later with [prefetch].
///
/// All current operations can be cancelled and future operations removed from
/// the queue with [stop].
///
/// Errors thrown by tasks scheduled with [prefetch] will only be triggered when
/// you await the Future returned by [fetch].
///
/// The operation will run in the [Zone] that the task was in when enqueued.
/// If a task if [prefetch]ed and later [fetch]ed before the operation is
/// started, the task will go in front of the queue with the zone of the [fetch]
/// operation.
///
/// Example:
///
/// ```dart
/// // A retriever that, given a uri, gets that page and returns the body
/// final retriever = Retriever(
///     (Uri uri, _) => return CancelableOperation.fromFuture(http.read(uri)));
/// // Start fetching `pub.dev` in the background.
/// retriever.prefetch(Uri.parse('https://pub.dev/'));
/// // ... do time-consuming task.
///
/// // Now we actually need `pub.dev`.
/// final pubDevBody = await retriever.fetch(Uri.parse('https://pub.dev/'));
/// ```
class Retriever<K, V> {
  final CancelableOperation<V> Function(K, Retriever) _run;

  /// The results of ongoing and finished computations.
  final Map<K, Completer<V>> _cache = <K, Completer<V>>{};

  /// Operations that are waiting to run.
  final Queue<_TaskWithZone<K>> _queue = Queue<_TaskWithZone<K>>();

  /// Rate limits the downloads.
  final Pool _pool;

  /// The currently active operations.
  final Map<K, CancelableOperation<V>> _active = <K, CancelableOperation<V>>{};

  /// True when the processing loop is running.
  bool _started = false;

  Retriever(CancelableOperation<V> Function(K, Retriever) run,
      {maxConcurrentOperations = 10})
      : _run = run,
        _pool = Pool(maxConcurrentOperations);

  Retriever.nonCancelable(Future<V> Function(K, Retriever) run,
      {maxConcurrentOperations = 10})
      : this(
            (key, retriever) =>
                CancelableOperation.fromFuture(run(key, retriever)),
            maxConcurrentOperations: maxConcurrentOperations);

  /// Starts running operations from the queue. Taking the first items first.
  void _process() async {
    assert(!_started);
    _started = true;
    while (_queue.isNotEmpty) {
      final resource = await _pool.request();
      // This checks if [stop] has been called while waiting for a resource.
      if (!_started) {
        resource.release();
        break;
      }
      // Take the highest priority task from the queue.
      final taskWithZone = _queue.removeFirst();
      final task = taskWithZone.task;
      // Create or get the completer to deliver the result to.
      final completer = _cache.putIfAbsent(
          task,
          () => Completer()
            // Listen to errors: this will make errors thrown by [_get] not
            // become uncaught.
            // They will still show up for other listeners of the future.
            ..future.catchError((error) {}));
      // Already done or already scheduled => do nothing.
      if (completer.isCompleted || _active.containsKey(task)) {
        resource.release();
        continue;
      }

      // Start running the operation for [task] in the original [Zone].
      final zone = taskWithZone.zone;
      final operation = zone.runBinary(_run, task, this);
      _active[task] = operation;
      operation
          .then(completer.complete, onError: completer.completeError)
          .value
          .whenComplete(() {
        resource.release();
        _active.remove(task);
      });
    }
    _started = false;
  }

  /// Cancels all active computations, and clears the queue.
  void stop() {
    // Stop the processing loop.
    _started = false;
    // Cancel all active operations.
    for (final operation in _active.values) {
      operation.cancel();
    }
    // Do not process the rest of the queue.
    _queue.clear();
  }

  /// Puts [task] in the back of the work queue.
  ///
  /// Task will be processed when there are free resources, and other already
  /// queued tasks are done.
  void prefetch(K task) {
    _queue.addLast(_TaskWithZone.current(task));
    if (!_started) _process();
  }

  /// Returns the result of running [task].
  ///
  /// If [task] is already done, the cached result will be returned.
  /// If [task] is not yet active, it will go to the front of the work queue
  /// to be scheduled next when there are free resources.
  Future<V> fetch(K task) {
    final completer = _cache.putIfAbsent(task, () => Completer());
    if (!completer.isCompleted) {
      // We allow adding the same task twice to the queue.
      // It will get dedupped by the [_process] loop.
      _queue.addFirst(_TaskWithZone.current(task));
      if (!_started) _process();
    }
    return completer.future;
  }
}

class _TaskWithZone<K> {
  final K task;
  final Zone zone;
  _TaskWithZone(this.task, this.zone);
  _TaskWithZone.current(K task) : this(task, Zone.current);
}
