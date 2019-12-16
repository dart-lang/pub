// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import "dart:collection";

import "package:pool/pool.dart";
import "package:async/async.dart";

/// Handles rate-limited scheduling of tasks.
///
/// Designed to allow prefetching tasks that will likely be needed
/// later with [prefetch].
///
/// All current operations can be cancelled and future operations removed from
/// the queue with [stop].
///
/// Errors thrown by tasks scheduled with [prefetch] will only be triggered when
/// you await to the Future returned by [fetch].
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
  final CancelableOperation<V> Function(K, Retriever) _get;
  final Map<K, Completer<V>> _cache = <K, Completer<V>>{};

  /// Operations that are waiting to run.
  final Queue<K> _queue = Queue<K>();

  final Pool _pool;

  /// The active operations
  final Map<K, CancelableOperation<V>> _active = <K, CancelableOperation<V>>{};
  bool started = false;

  Retriever(this._get, {maxConcurrentOperations = 10})
      : _pool = Pool(maxConcurrentOperations);

  /// Starts running operations from the queue. Taking the first items first.
  void _process() async {
    assert(!started);
    started = true;
    while (_queue.isNotEmpty) {
      final resource = await _pool.request();
      // This checks if [stop] has been called while waiting for a resource.
      if (!started) {
        resource.release();
        break;
      }
      // Take the highest priority task from the queue.
      final task = _queue.removeFirst();
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

      // Run operation task.
      final operation = _get(task, this);
      _active[task] = operation;
      operation
          .then(completer.complete, onError: completer.completeError)
          .value
          .whenComplete(() {
        resource.release();
        _active.remove(task);
      });
    }
    started = false;
  }

  /// Cancels all active computations, and clears the queue.
  void stop() {
    // Stop the processing loop
    started = false;
    // Cancel all active operatios
    for (final operation in _active.values) {
      operation.cancel();
    }
    // Do not process anymore.
    _queue.clear();
  }

  /// Puts [task] in the back of the work queue.
  ///
  /// Tasl will be processed when there are free resources, and other already
  /// queued tasks are done.
  void prefetch(K task) {
    _queue.addLast(task);
    if (!started) _process();
  }

  /// Returns the result of running [task].
  ///
  /// If [task] is already done, the cached result will be returned.
  /// If [task] is not yet active, it will go to the front of the work queue
  /// to be scheduled when there are free resources.
  Future<V> fetch(K task) {
    final completer = _cache.putIfAbsent(task, () => Completer());
    if (!completer.isCompleted) {
      // We don't worry about adding the same task twice.
      // It will get dedupped by the [_process] loop.
      _queue.addFirst(task);
      if (!started) _process();
    }
    return completer.future;
  }
}
