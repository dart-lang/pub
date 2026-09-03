// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'io.dart';
import 'log.dart' as log;
import 'utils.dart';

/// Tracks elapsed time and progress display state to debounce initial
/// spinners across a group of related operations.
final class ProgressGracePeriod {
  /// The default grace period before transient progress is shown for the first
  /// time.
  final Duration _defaultGracePeriod;

  /// Stopwatch tracking time since program start or since last non-progress
  /// output.
  final Stopwatch _stopwatch;

  /// Whether a progress message has been displayed since the last reset.
  bool _hasShownProgress;

  /// Whether a progress message has been displayed since the last reset.
  bool get hasShownProgress => _hasShownProgress;

  /// Creates a [ProgressGracePeriod] with an optional [defaultGracePeriod].
  ///
  /// It is an error if [defaultGracePeriod] is negative.
  ProgressGracePeriod({
    Duration defaultGracePeriod = const Duration(milliseconds: 500),
    Stopwatch? stopwatch,
    bool hasShownProgress = false,
  }) : _defaultGracePeriod = defaultGracePeriod,
       _stopwatch = stopwatch ?? (Stopwatch()..start()),
       _hasShownProgress = hasShownProgress {
    if (defaultGracePeriod.isNegative) {
      throw ArgumentError.value(
        defaultGracePeriod,
        'defaultGracePeriod',
        'Must not be negative',
      );
    }
  }

  /// Resets the grace period timer and progress flag.
  void reset() {
    _stopwatch.reset();
    _hasShownProgress = false;
  }

  /// Calculates the effective delay before transient progress should appear.
  Duration get remainingDelay {
    if (_hasShownProgress) return Duration.zero;
    final remaining = _defaultGracePeriod - _stopwatch.elapsed;
    return remaining < Duration.zero ? Duration.zero : remaining;
  }

  /// Marks that progress has been shown.
  void markProgressShown() {
    _hasShownProgress = true;
  }
}

final _defaultProgressGracePeriod = ProgressGracePeriod();

final _progressGracePeriodKey = Object();

/// The [ProgressGracePeriod] used by the current [Zone].
ProgressGracePeriod get currentProgressGracePeriod =>
    Zone.current[_progressGracePeriodKey] as ProgressGracePeriod? ??
    _defaultProgressGracePeriod;

/// Resets the shared grace period timer.
void resetGracePeriod() {
  currentProgressGracePeriod.reset();
}

/// Runs [callback] in a [Zone] with [progressGracePeriod] as the active grace
/// period.
R withProgressGracePeriod<R>(
  R Function() callback, {
  required ProgressGracePeriod progressGracePeriod,
}) => runZoned(
  callback,
  zoneValues: {_progressGracePeriodKey: progressGracePeriod},
);

/// A live-updating progress indicator for long-running log entries.
final class Progress {
  /// The timer used to write "..." during a progress log.
  Timer? _timer;

  /// The [Stopwatch] used to track how long a progress log has been running.
  final _stopwatch = Stopwatch();

  /// The progress message as it's being incrementally appended.
  ///
  /// When the progress is done, a single entry will be added to the log for it.
  final String _message;

  /// Gets the current progress time as a parenthesized, formatted string.
  String get _time => '(${niceDuration(_stopwatch.elapsed)})';

  /// The length of the most recently-printed [_time] string.
  var _timeLength = 0;

  /// Whether the initial start message has been printed.
  var _hasStarted = false;

  /// Whether this progress indicator is transient (erased upon completion).
  final bool _transient;

  /// Creates a new progress indicator.
  ///
  /// If [fine] is passed, this will log progress messages on [log.Level.fine]
  /// as opposed to [log.Level.message].
  ///
  /// If [delay] is passed, the progress animation is only displayed if the
  /// operation takes longer than [delay].
  ///
  /// If [transient] is `true`, the progress message will produce no output when
  /// not running in a terminal (unless verbose logging is active).
  Progress(
    this._message, {
    bool fine = false,
    Duration? delay,
    bool transient = false,
  }) : _transient = transient {
    _stopwatch.start();

    final level = fine ? log.Level.fine : log.Level.message;

    // The animation is only shown when it would be meaningful to a human.
    // That means we're writing a visible message to a TTY at normal log levels
    // with ANSI support and non-JSON output.
    if (!terminalOutputForStdout ||
        !canUseAnsiCodes ||
        !log.verbosity.isLevelVisible(level) ||
        fine ||
        log.verbosity.isLevelVisible(log.Level.fine)) {
      if (transient && !log.verbosity.isLevelVisible(log.Level.fine)) {
        return;
      }
      // Not animating, so just log the start and wait until the task is
      // completed.
      log.write(level, '$_message...');
      return;
    }

    final effectiveDelay = delay ?? Duration.zero;

    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_stopwatch.elapsed < effectiveDelay) return;
      if (!_hasStarted) {
        stdout.write('$_message... ');
        _hasStarted = true;
        currentProgressGracePeriod.markProgressShown();
      }
      _update();
    });

    if (effectiveDelay == Duration.zero) {
      stdout.write('$_message... ');
      _hasStarted = true;
      currentProgressGracePeriod.markProgressShown();
    }
  }

  /// Erases the progress message from the terminal.
  void _erase() {
    stdout.write('\r${log.eraseLine}');
  }

  /// Stops the progress indicator and prints the final elapsed time.
  void stop() {
    _stopwatch.stop();

    // Always log the final time as [log.fine] because for the most part normal
    // users don't care about the precise time information beyond what's shown
    // in the animation.
    log.fine('$_message finished $_time.');

    // If we were animating, print one final update to show the user the final
    // time.
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    if (_hasStarted) {
      _update();
      stdout.writeln();
    }
  }

  /// Erases the progress message from the terminal and stops the progress
  /// indicator.
  void stopAndClear() {
    _stopwatch.stop();

    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      if (_hasStarted) {
        _erase();
      }
    }

    // Always log the final time as [log.fine] because for the most part normal
    // users don't care about the precise time information beyond what's shown
    // in the animation.
    log.fine('$_message finished $_time.');
  }

  /// Stop animating the progress indicator.
  ///
  /// This will continue running the stopwatch so that the full time can be
  /// logged in [stop].
  void stopAnimating() {
    if (_timer == null) return;

    if (_hasStarted) {
      if (_transient) {
        _erase();
      } else {
        // Erase the time indicator so that we don't leave a misleading
        // half-complete time indicator on the console.
        stdout.write('\r$_message... ${log.eraseToLineEnd}');
        stdout.writeln();
      }
    }
    _timeLength = 0;
    _timer!.cancel();
    _timer = null;
  }

  /// Refreshes the progress line.
  void _update() {
    if (log.isMuted) return;

    // Show the time only once it gets noticeably long.
    if (_stopwatch.elapsed.inSeconds == 0) return;

    // Erase the last time that was printed. Erasing just the time using `\b`
    // rather than using `\r` to erase the entire line ensures that we don't
    // spam progress lines if they're wider than the terminal width.
    stdout.write('\b' * _timeLength);
    final time = _time;
    _timeLength = time.length;
    stdout.write(log.gray(time));
  }
}
