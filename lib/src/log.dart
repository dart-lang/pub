// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Message logging.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:stack_trace/stack_trace.dart';

import 'exceptions.dart';
import 'io.dart';
import 'progress.dart';
import 'transcript.dart';
import 'utils.dart';

/// The singleton instance so that we can have a nice api like:
///
///     log.json.error(...);
final json = new _JsonLogger();

/// The current logging verbosity.
Verbosity verbosity = Verbosity.NORMAL;

/// Whether or not to log entries with prejudice.
bool withPrejudice = false;

/// Whether or not to log entries sparklily.
bool sparkle = false;

/// In cases where there's a ton of log spew, make sure we don't eat infinite
/// memory.
///
/// This can occur when the backtracking solver stumbles into a pathological
/// dependency graph. It generally will find a solution, but it may log
/// thousands and thousands of entries to get there.
const _MAX_TRANSCRIPT = 10000;

/// The list of recorded log messages. Will only be recorded if
/// [recordTranscript()] is called.
Transcript<Entry> _transcript;

/// The currently-animated progress indicator, if any.
///
/// This will also be in [_progresses].
Progress _animatedProgress;

_Collapser _collapser;

final _cyan = getSpecial('\u001b[36m');
final _green = getSpecial('\u001b[32m');
final _magenta = getSpecial('\u001b[35m');
final _red = getSpecial('\u001b[31m');
final _yellow = getSpecial('\u001b[33m');
final _blue = getSpecial('\u001b[34m');
final _gray = getSpecial('\u001b[1;30m');
final _none = getSpecial('\u001b[0m');
final _noColor = getSpecial('\u001b[39m');
final _bold = getSpecial('\u001b[1m');

/// All color codees.
var _allColors = [_cyan, _green, _magenta, _red, _yellow, _blue, ''];

/// An enum type for defining the different logging levels a given message can
/// be associated with.
///
/// By default, [ERROR] and [WARNING] messages are printed to sterr. [MESSAGE]
/// messages are printed to stdout, and others are ignored.
class Level {
  /// An error occurred and an operation could not be completed.
  ///
  /// Usually shown to the user on stderr.
  static const ERROR = const Level._("ERR ");

  /// Something unexpected happened, but the program was able to continue,
  /// though possibly in a degraded fashion.
  static const WARNING = const Level._("WARN");

  /// A message intended specifically to be shown to the user.
  static const MESSAGE = const Level._("MSG ");

  /// Some interaction with the external world occurred, such as a network
  /// operation, process spawning, or file IO.
  static const IO = const Level._("IO  ");

  /// Incremental output during pub's version constraint solver.
  static const SOLVER = const Level._("SLVR");

  /// Fine-grained and verbose additional information.
  ///
  /// Used to provide program state context for other logs (such as what pub
  /// was doing when an IO operation occurred) or just more detail for an
  /// operation.
  static const FINE = const Level._("FINE");

  const Level._(this.name);
  final String name;

  String toString() => name;
}

typedef _LogFn(Entry entry);

/// An enum type to control which log levels are displayed and how they are
/// displayed.
class Verbosity {
  /// Silence all logging.
  static const NONE = const Verbosity._("none", const {
    Level.ERROR: null,
    Level.WARNING: null,
    Level.MESSAGE: null,
    Level.IO: null,
    Level.SOLVER: null,
    Level.FINE: null
  });

  /// Shows only errors.
  static const ERROR = const Verbosity._("error", const {
    Level.ERROR: _logToStderr,
    Level.WARNING: null,
    Level.MESSAGE: null,
    Level.IO: null,
    Level.SOLVER: null,
    Level.FINE: null
  });

  /// Shows only errors and warnings.
  static const WARNING = const Verbosity._("warning", const {
    Level.ERROR: _logToStderr,
    Level.WARNING: _logToStderr,
    Level.MESSAGE: null,
    Level.IO: null,
    Level.SOLVER: null,
    Level.FINE: null
  });

  /// The default verbosity which shows errors, warnings, and messages.
  static const NORMAL = const Verbosity._("normal", const {
    Level.ERROR: _logToStderr,
    Level.WARNING: _logToStderr,
    Level.MESSAGE: _logToStdout,
    Level.IO: null,
    Level.SOLVER: null,
    Level.FINE: null
  });

  /// Shows errors, warnings, messages, and IO event logs.
  static const IO = const Verbosity._("io", const {
    Level.ERROR: _logToStderrWithLabel,
    Level.WARNING: _logToStderrWithLabel,
    Level.MESSAGE: _logToStdoutWithLabel,
    Level.IO: _logToStderrWithLabel,
    Level.SOLVER: null,
    Level.FINE: null
  });

  /// Shows errors, warnings, messages, and version solver logs.
  static const SOLVER = const Verbosity._("solver", const {
    Level.ERROR: _logToStderr,
    Level.WARNING: _logToStderr,
    Level.MESSAGE: _logToStdout,
    Level.IO: null,
    Level.SOLVER: _logToStdout,
    Level.FINE: null
  });

  /// Shows all logs.
  static const ALL = const Verbosity._("all", const {
    Level.ERROR: _logToStderrWithLabel,
    Level.WARNING: _logToStderrWithLabel,
    Level.MESSAGE: _logToStdoutWithLabel,
    Level.IO: _logToStderrWithLabel,
    Level.SOLVER: _logToStderrWithLabel,
    Level.FINE: _logToStderrWithLabel
  });

  const Verbosity._(this.name, this._loggers);
  final String name;
  final Map<Level, _LogFn> _loggers;

  /// Returns whether or not logs at [level] will be printed.
  bool isLevelVisible(Level level) => _loggers[level] != null;

  String toString() => name;
}

/// A single log entry.
class Entry {
  final Level level;
  final List<String> lines;

  Entry(this.level, this.lines);
}

/// Logs [message] at [Level.ERROR].
///
/// If [error] is passed, it's appended to [message]. If [trace] is passed, it's
/// printed at log level fine.
void error(message, [error, StackTrace trace]) {
  message ??= '';
  if (error != null) {
    message = message.isEmpty ? "$error" : "$message: $error";
    if (error is Error && trace == null) trace = error.stackTrace;
  }
  write(Level.ERROR, message);
  if (trace != null) write(Level.FINE, new Chain.forTrace(trace));
}

/// Logs [message] at [Level.WARNING].
void warning(message) => write(Level.WARNING, message);

/// Logs [message] at [Level.MESSAGE].
void message(message) => write(Level.MESSAGE, message);

/// Logs [message] at [Level.IO].
void io(message) => write(Level.IO, message);

/// Logs [message] at [Level.SOLVER].
void solver(message) => write(Level.SOLVER, message);

/// Logs [message] at [Level.FINE].
void fine(message) => write(Level.FINE, message);

/// Logs [message] at [level].
void write(Level level, message) {
  // Don't allow interleaving collapsible messages with other kinds.
  if (_collapser != null) _collapser.end();

  message = message.toString();
  var lines = splitLines(message);

  // Discard a trailing newline. This is useful since StringBuffers often end
  // up with an extra newline at the end from using [writeln].
  if (lines.isNotEmpty && lines.last == "") {
    lines.removeLast();
  }

  var entry = new Entry(level, lines.map(format).toList());

  var logFn = verbosity._loggers[level];
  if (logFn != null) logFn(entry);

  if (_transcript != null) _transcript.add(entry);
}

final _capitalizedAnsiEscape = new RegExp(r'\u001b\[\d+(;\d+)?M');

/// Returns [string] formatted as it would be if it were logged.
String format(String string) {
  if (sparkle) {
    string = string.replaceAllMapped(new RegExp(r'.'), (match) {
      var char = "${choose(_allColors)}${match[0]}$_noColor";
      return (withPrejudice || random.nextBool()) ? char : "$_bold$char$_none";
    });
  }

  if (withPrejudice) {
    // [toUpperCase] can corrupt terminal colorings, so fix them up using
    // [replaceAllMapped].
    string = string.toUpperCase().replaceAllMapped(
        _capitalizedAnsiEscape, (match) => match[0].toLowerCase());

    // Don't use [bold] because it's disabled under [withPrejudice].
    string = "$_bold$string$_none";
  }

  return string;
}

/// Logs an asynchronous IO operation.
///
/// Logs [startMessage] before the operation starts, then when [operation]
/// completes, invokes [endMessage] with the completion value and logs the
/// result of that. Returns a future that completes after the logging is done.
///
/// If [endMessage] is omitted, then logs "Begin [startMessage]" before the
/// operation and "End [startMessage]" after it.
Future ioAsync(String startMessage, Future operation,
    [String endMessage(value)]) {
  if (endMessage == null) {
    io("Begin $startMessage.");
  } else {
    io(startMessage);
  }

  return operation.then((result) {
    if (endMessage == null) {
      io("End $startMessage.");
    } else {
      io(endMessage(result));
    }
    return result;
  });
}

/// Logs the spawning of an [executable] process with [arguments] at [IO]
/// level.
void process(
    String executable, List<String> arguments, String workingDirectory) {
  io("Spawning \"$executable ${arguments.join(' ')}\" in "
      "${p.absolute(workingDirectory)}");
}

/// Logs the results of running [executable].
void processResult(String executable, PubProcessResult result) {
  // Log it all as one message so that it shows up as a single unit in the logs.
  var buffer = new StringBuffer();
  buffer.writeln("Finished $executable. Exit code ${result.exitCode}.");

  dumpOutput(String name, List<String> output) {
    if (output.length == 0) {
      buffer.writeln("Nothing output on $name.");
    } else {
      buffer.writeln("$name:");
      var numLines = 0;
      for (var line in output) {
        if (++numLines > 1000) {
          buffer.writeln('[${output.length - 1000}] more lines of output '
              'truncated...]');
          break;
        }

        buffer.writeln("| $line");
      }
    }
  }

  dumpOutput("stdout", result.stdout);
  dumpOutput("stderr", result.stderr);

  io(buffer.toString().trim());
}

/// Logs an exception.
void exception(exception, [StackTrace trace]) {
  if (exception is SilentException) return;

  var chain = trace == null ? new Chain.current() : new Chain.forTrace(trace);

  // This is basically the top-level exception handler so that we don't
  // spew a stack trace on our users.
  if (exception is SourceSpanException) {
    error(exception.toString(color: canUseSpecialChars));
  } else {
    error(getErrorMessage(exception));
  }
  fine("Exception type: ${exception.runtimeType}");

  if (json.enabled) {
    if (exception is UsageException) {
      // Don't print usage info in JSON output.
      json.error(exception.message);
    } else {
      json.error(exception);
    }
  }

  if (!isUserFacingException(exception)) {
    error(chain.terse);
  } else {
    fine(chain.terse);
  }

  if (exception is WrappedException && exception.innerError != null) {
    var message = "Wrapped exception: ${exception.innerError}";
    if (exception.innerChain != null) {
      message = "$message\n${exception.innerChain}";
    }
    fine(message);
  }
}

/// Enables recording of log entries.
void recordTranscript() {
  _transcript = new Transcript<Entry>(_MAX_TRANSCRIPT);
}

/// If [recordTranscript()] was called, then prints the previously recorded log
/// transcript to stderr.
void dumpTranscript() {
  if (_transcript == null) return;

  stderr.writeln('---- Log transcript ----');
  _transcript.forEach((entry) {
    _printToStream(stderr, entry, showLabel: true);
  }, (discarded) {
    stderr.writeln('---- ($discarded discarded) ----');
  });
  stderr.writeln('---- End log transcript ----');
}

/// Prints [message] then displays an updated elapsed time until the future
/// returned by [callback] completes.
///
/// If anything else is logged during this (including another call to
/// [progress]) that cancels the progress animation, although the total time
/// will still be printed once it finishes. If [fine] is passed, the progress
/// information will only be visible at [Level.FINE].
Future/*<T>*/ progress/*<T>*/(String message, Future/*<T>*/ callback(),
    {bool fine: false}) {
  _stopProgress();

  var progress = new Progress(message, fine: fine);
  _animatedProgress = progress;
  return callback().whenComplete(progress.stop);
}

/// Stops animating the running progress indicator, if currently running.
void _stopProgress() {
  if (_animatedProgress != null) _animatedProgress.stopAnimating();
  _animatedProgress = null;
}

/// The number of outstanding calls to [muteProgress] that have not been unmuted
/// yet.
int _numMutes = 0;

/// Whether progress animation should be muted or not.
bool get isMuted => _numMutes > 0;

/// Stops animating any ongoing progress.
///
/// This is called before spawning Git since Git sometimes writes directly to
/// the terminal to ask for login credentials, which would then get overwritten
/// by the progress animation.
///
/// Each call to this must be paired with a call to [unmuteProgress].
void muteProgress() {
  _numMutes++;
}

/// Resumes animating any ongoing progress once all calls to [muteProgress]
/// have made their matching [unmuteProgress].
void unmuteProgress() {
  assert(_numMutes > 0);
  _numMutes--;
}

/// Logs a collapsible [message].
///
/// If a number of collapsible messages are printed in short succession, they
/// are collapsed to just showing [template] with "##" replaced with the number
/// of collapsed messages. Avoids spamming the output with not-very-interesting
/// output.
void collapsible(String message, String template) {
  // Only collapse messages when the output is not verbose.
  if (verbosity._loggers[Level.MESSAGE] != _logToStdout) {
    write(Level.MESSAGE, message);
    return;
  }

  // If this is a different set of collapsed messages, end the previous ones.
  if (_collapser != null && _collapser._template != template) {
    _collapser.end();
  }

  if (_collapser != null) {
    _collapser.increment();
  } else {
    _collapser = new _Collapser(message, template);
  }
}

/// Wraps [text] in the ANSI escape codes to make it bold when on a platform
/// that supports that.
///
/// Use this to highlight the most important piece of a long chunk of text.
///
/// This is disabled under [withPrejudice] since all text is bold with
/// prejudice.
String bold(text) => (withPrejudice || sparkle) ? "$text" : "$_bold$text$_none";

/// Wraps [text] in the ANSI escape codes to make it gray when on a platform
/// that supports that.
///
/// Use this for text that's less important than the text around it.
///
/// The gray marker also enables bold, so it needs to be handled specially with
/// [withPrejudice] to avoid disabling bolding entirely.
String gray(text) {
  if (sparkle) return "$text";
  if (withPrejudice) return "$_gray$text$_noColor";
  return "$_gray$text$_none";
}

/// Wraps [text] in the ANSI escape codes to color it cyan when on a platform
/// that supports that.
///
/// Use this to highlight something interesting but neither good nor bad.
String cyan(text) => sparkle ? "$text" : "$_cyan$text$_noColor";

/// Wraps [text] in the ANSI escape codes to color it green when on a platform
/// that supports that.
///
/// Use this to highlight something successful or otherwise positive.
String green(text) => sparkle ? "$text" : "$_green$text$_noColor";

/// Wraps [text] in the ANSI escape codes to color it magenta when on a
/// platform that supports that.
///
/// Use this to highlight something risky that the user should be aware of but
/// may intend to do.
String magenta(text) => sparkle ? "$text" : "$_magenta$text$_noColor";

/// Wraps [text] in the ANSI escape codes to color it red when on a platform
/// that supports that.
///
/// Use this to highlight unequivocal errors, problems, or failures.
String red(text) => sparkle ? "$text" : "$_red$text$_noColor";

/// Wraps [text] in the ANSI escape codes to color it yellow when on a platform
/// that supports that.
///
/// Use this to highlight warnings, cautions or other things that are bad but
/// do not prevent the user's goal from being reached.
String yellow(text) => sparkle ? "$text" : "$_yellow$text$_noColor";

/// Log function that prints the message to stdout.
void _logToStdout(Entry entry) {
  _logToStream(stdout, entry, showLabel: false);
}

/// Log function that prints the message to stdout with the level name.
void _logToStdoutWithLabel(Entry entry) {
  _logToStream(stdout, entry, showLabel: true);
}

/// Log function that prints the message to stderr.
void _logToStderr(Entry entry) {
  _logToStream(stderr, entry, showLabel: false);
}

/// Log function that prints the message to stderr with the level name.
void _logToStderrWithLabel(Entry entry) {
  _logToStream(stderr, entry, showLabel: true);
}

void _logToStream(IOSink sink, Entry entry, {bool showLabel}) {
  if (json.enabled) return;

  _printToStream(sink, entry, showLabel: showLabel);
}

void _printToStream(IOSink sink, Entry entry, {bool showLabel}) {
  _stopProgress();

  bool firstLine = true;
  for (var line in entry.lines) {
    if (showLabel) {
      if (firstLine) {
        sink.write('${entry.level.name}: ');
      } else {
        sink.write('    | ');
      }
    }

    sink.writeln(line);

    firstLine = false;
  }
}

/// Namespace-like class for collecting the methods for JSON logging.
class _JsonLogger {
  /// Whether logging should use machine-friendly JSON output or human-friendly
  /// text.
  ///
  /// If set to `true`, then no regular logging is printed. Logged messages
  /// will still be recorded and displayed if the transcript is printed.
  bool enabled = false;

  /// Creates an error JSON object for [error] and prints it if JSON output
  /// is enabled.
  ///
  /// Always prints to stdout.
  void error(error, [stackTrace]) {
    var errorJson = {"error": error.toString()};

    if (stackTrace == null && error is Error) stackTrace = error.stackTrace;
    if (stackTrace != null) {
      errorJson["stackTrace"] = new Chain.forTrace(stackTrace).toString();
    }

    // If the error came from a file, include the path.
    if (error is SourceSpanException && error.span.sourceUrl != null) {
      // Normalize paths and make them absolute for backwards compatibility with
      // the protocol used by the analyzer.
      errorJson["path"] =
          p.normalize(p.absolute(p.fromUri(error.span.sourceUrl)));
    }

    if (error is FileException) {
      errorJson["path"] = p.normalize(p.absolute(error.path));
    }

    this.message(errorJson);
  }

  /// Encodes [message] to JSON and prints it if JSON output is enabled.
  void message(message) {
    if (!enabled) return;

    print(JSON.encode(message));
  }
}

/// Collapses a series of collapsible messages into a single line of output if
/// they happen within a short window of time.
class _Collapser {
  /// The window of time where a series of calls to [collapsible] will be
  /// collapsed to a single message.
  static final _window = new Duration(milliseconds: 100);

  /// The Timer used to coalesce a number of collapsible messages.
  ///
  /// This is `null` if no collapsible messages are waiting to be displayed.
  Timer _timer;

  /// The first collapsible message waiting to be displayed.
  String _firstMessage;

  /// The template used to display the number of collapsed messages when more
  /// than one collapsible message is logged within the window of time.
  ///
  /// Inside the template, "##" will be replaced with the number of collapsed
  /// messages.
  String _template;

  /// The number of collapsible messages that are waiting to be logged.
  int _count = 1;

  _Collapser(this._firstMessage, this._template) {
    _initTimer();
  }

  void increment() {
    // Reset the timer.
    _timer.cancel();
    _initTimer();

    _count++;
  }

  void end() {
    // Clear this first so we don't stack overflow when we call message() below.
    _collapser = null;

    _timer.cancel();
    if (_count == 1) {
      message(_firstMessage);
    } else {
      message(_template.replaceAll("##", _count.toString()));
    }
  }

  void _initTimer() {
    _timer = new Timer(_window, end);
  }
}
