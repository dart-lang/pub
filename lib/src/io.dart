// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helper functionality to make working with IO easier.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:http/http.dart' show ByteStream;
import 'package:http_multi_server/http_multi_server.dart';
import 'package:path/path.dart' as path;
import 'package:pedantic/pedantic.dart';
import 'package:pool/pool.dart';
import 'package:stack_trace/stack_trace.dart';

import 'error_group.dart';
import 'exceptions.dart';
import 'exit_codes.dart' as exit_codes;
import 'log.dart' as log;
import 'sdk.dart';
import 'utils.dart';

export 'package:http/http.dart' show ByteStream;

/// The pool used for restricting access to asynchronous operations that consume
/// file descriptors.
///
/// The maximum number of allocated descriptors is based on empirical tests that
/// indicate that beyond 32, additional file reads don't provide substantial
/// additional throughput.
final _descriptorPool = Pool(32);

/// Determines if a file or directory exists at [path].
bool entryExists(String path) =>
    dirExists(path) || fileExists(path) || linkExists(path);

/// Returns whether [link] exists on the file system.
///
/// This returns `true` for any symlink, regardless of what it points at or
/// whether it's broken.
bool linkExists(String link) => Link(link).existsSync();

/// Returns whether [file] exists on the file system.
///
/// This returns `true` for a symlink only if that symlink is unbroken and
/// points to a file.
bool fileExists(String file) => File(file).existsSync();

/// Returns the canonical path for [pathString].
///
/// This is the normalized, absolute path, with symlinks resolved. As in
/// [transitiveTarget], broken or recursive symlinks will not be fully resolved.
///
/// This doesn't require [pathString] to point to a path that exists on the
/// filesystem; nonexistent or unreadable path entries are treated as normal
/// directories.
String canonicalize(String pathString) {
  var seen = <String>{};
  var components =
      Queue<String>.from(path.split(path.normalize(path.absolute(pathString))));

  // The canonical path, built incrementally as we iterate through [components].
  var newPath = components.removeFirst();

  // Move through the components of the path, resolving each one's symlinks as
  // necessary. A resolved component may also add new components that need to be
  // resolved in turn.
  while (components.isNotEmpty) {
    seen.add(path.join(newPath, path.joinAll(components)));
    var resolvedPath =
        _resolveLink(path.join(newPath, components.removeFirst()));
    var relative = path.relative(resolvedPath, from: newPath);

    // If the resolved path of the component relative to `newPath` is just ".",
    // that means component was a symlink pointing to its parent directory. We
    // can safely ignore such components.
    if (relative == '.') continue;

    var relativeComponents = Queue<String>.from(path.split(relative));

    // If the resolved path is absolute relative to `newPath`, that means it's
    // on a different drive. We need to canonicalize the entire target of that
    // symlink again.
    if (path.isAbsolute(relative)) {
      // If we've already tried to canonicalize the new path, we've encountered
      // a symlink loop. Avoid going infinite by treating the recursive symlink
      // as the canonical path.
      if (seen.contains(relative)) {
        newPath = relative;
      } else {
        newPath = relativeComponents.removeFirst();
        relativeComponents.addAll(components);
        components = relativeComponents;
      }
      continue;
    }

    // Pop directories off `newPath` if the component links upwards in the
    // directory hierarchy.
    while (relativeComponents.first == '..') {
      newPath = path.dirname(newPath);
      relativeComponents.removeFirst();
    }

    // If there's only one component left, [resolveLink] guarantees that it's
    // not a link (or is a broken link). We can just add it to `newPath` and
    // continue resolving the remaining components.
    if (relativeComponents.length == 1) {
      newPath = path.join(newPath, relativeComponents.single);
      continue;
    }

    // If we've already tried to canonicalize the new path, we've encountered a
    // symlink loop. Avoid going infinite by treating the recursive symlink as
    // the canonical path.
    var newSubPath = path.join(newPath, path.joinAll(relativeComponents));
    if (seen.contains(newSubPath)) {
      newPath = newSubPath;
      continue;
    }

    // If there are multiple new components to resolve, add them to the
    // beginning of the queue.
    relativeComponents.addAll(components);
    components = relativeComponents;
  }
  return newPath;
}

/// Returns the transitive target of [link] (if A links to B which links to C,
/// this will return C).
///
/// If [link] is part of a symlink loop (e.g. A links to B which links back to
/// A), this returns the path to the first repeated link (so
/// `transitiveTarget("A")` would return `"A"` and `transitiveTarget("A")` would
/// return `"B"`).
///
/// This accepts paths to non-links or broken links, and returns them as-is.
String _resolveLink(String link) {
  var seen = <String>{};
  while (linkExists(link) && seen.add(link)) {
    link =
        path.normalize(path.join(path.dirname(link), Link(link).targetSync()));
  }
  return link;
}

/// Reads the contents of the text file [file].
String readTextFile(String file) => File(file).readAsStringSync(encoding: utf8);

/// Reads the contents of the binary file [file].
List<int> readBinaryFile(String file) {
  log.io('Reading binary file $file.');
  var contents = File(file).readAsBytesSync();
  log.io('Read ${contents.length} bytes from $file.');
  return contents;
}

/// Creates [file] and writes [contents] to it.
///
/// If [dontLogContents] is `true`, the contents of the file will never be
/// logged.
String writeTextFile(String file, String contents,
    {bool dontLogContents = false, Encoding encoding}) {
  encoding ??= utf8;

  // Sanity check: don't spew a huge file.
  log.io('Writing ${contents.length} characters to text file $file.');
  if (!dontLogContents && contents.length < 1024 * 1024) {
    log.fine('Contents:\n$contents');
  }

  deleteIfLink(file);
  File(file).writeAsStringSync(contents, encoding: encoding);
  return file;
}

/// Writes [stream] to a new file at path [file].
///
/// Replaces any file already at that path. Completes when the file is done
/// being written.
Future<String> _createFileFromStream(Stream<List<int>> stream, String file) {
  // TODO(nweiz): remove extra logging when we figure out the windows bot issue.
  log.io('Creating $file from stream.');

  return _descriptorPool.withResource(() async {
    deleteIfLink(file);
    await stream.pipe(File(file).openWrite());
    log.fine('Created $file from stream.');
    return file;
  });
}

/// Deletes [file] if it's a symlink.
///
/// The [File] class overwrites the symlink targets when writing to a file,
/// which is never what we want, so this delete the symlink first if necessary.
void deleteIfLink(String file) {
  if (!linkExists(file)) return;
  log.io('Deleting symlink at $file.');
  Link(file).deleteSync();
}

/// Ensures that [dir] and all its parent directories exist.
///
/// If they don't exist, creates them.
String ensureDir(String dir) {
  Directory(dir).createSync(recursive: true);
  return dir;
}

/// Creates a temp directory in [dir], whose name will be [prefix] with
/// characters appended to it to make a unique name.
///
/// Returns the path of the created directory.
String createTempDir(String base, String prefix) {
  var tempDir = Directory(base).createTempSync(prefix);
  log.io('Created temp directory ${tempDir.path}');
  return tempDir.path;
}

/// Creates a temp directory in the system temp directory, whose name will be
/// 'pub_' with characters appended to it to make a unique name.
///
/// Returns the path of the created directory.
Future<String> _createSystemTempDir() async {
  var tempDir = await Directory.systemTemp.createTemp('pub_');
  log.io('Created temp directory ${tempDir.path}');
  return tempDir.resolveSymbolicLinksSync();
}

/// Lists the contents of [dir].
///
/// If [recursive] is `true`, lists subdirectory contents (defaults to `false`).
/// If [includeHidden] is `true`, includes files and directories beginning with
/// `.` (defaults to `false`). If [includeDirs] is `true`, includes directories
/// as well as files (defaults to `true`).
///
/// [whiteList] is a list of hidden filenames to include even when
/// [includeHidden] is `false`.
///
/// Note that dart:io handles recursive symlinks in an unfortunate way. You
/// end up with two copies of every entity that is within the recursive loop.
/// We originally had our own directory list code that addressed that, but it
/// had a noticeable performance impact. In the interest of speed, we'll just
/// live with that annoying behavior.
///
/// The returned paths are guaranteed to begin with [dir]. Broken symlinks won't
/// be returned.
List<String> listDir(String dir,
    {bool recursive = false,
    bool includeHidden = false,
    bool includeDirs = true,
    Iterable<String> whitelist}) {
  whitelist ??= [];
  var whitelistFilter = createFileFilter(whitelist);

  // This is used in some performance-sensitive paths and can list many, many
  // files. As such, it leans more heavily towards optimization as opposed to
  // readability than most code in pub. In particular, it avoids using the path
  // package, since re-parsing a path is very expensive relative to string
  // operations.
  return Directory(dir)
      .listSync(recursive: recursive, followLinks: true)
      .where((entity) {
        if (!includeDirs && entity is Directory) return false;
        if (entity is Link) return false;
        if (includeHidden) return true;

        // Using substring here is generally problematic in cases where dir has one
        // or more trailing slashes. If you do listDir("foo"), you'll get back
        // paths like "foo/bar". If you do listDir("foo/"), you'll get "foo/bar"
        // (note the trailing slash was dropped. If you do listDir("foo//"), you'll
        // get "foo//bar".
        //
        // This means if you strip off the prefix, the resulting string may have a
        // leading separator (if the prefix did not have a trailing one) or it may
        // not. However, since we are only using the results of that to call
        // contains() on, the leading separator is harmless.
        assert(entity.path.startsWith(dir));
        var pathInDir = entity.path.substring(dir.length);

        // If the basename is whitelisted, don't count its "/." as making the file
        // hidden.
        var whitelistedBasename =
            whitelistFilter.firstWhere(pathInDir.contains, orElse: () => null);
        if (whitelistedBasename != null) {
          pathInDir = pathInDir.substring(
              0, pathInDir.length - whitelistedBasename.length);
        }

        if (pathInDir.contains('/.')) return false;
        if (!Platform.isWindows) return true;
        return !pathInDir.contains('\\.');
      })
      .map((entity) => entity.path)
      .toList();
}

/// Returns whether [dir] exists on the file system.
///
/// This returns `true` for a symlink only if that symlink is unbroken and
/// points to a directory.
bool dirExists(String dir) => Directory(dir).existsSync();

/// Tries to resiliently perform [operation].
///
/// Some file system operations can intermittently fail on Windows because
/// other processes are locking a file. We've seen this with virus scanners
/// when we try to delete or move something while it's being scanned. To
/// mitigate that, on Windows, this will retry the operation a few times if it
/// fails.
void _attempt(String description, void Function() operation) {
  if (!Platform.isWindows) {
    operation();
    return;
  }

  String getErrorReason(FileSystemException error) {
    if (error.osError.errorCode == 5) {
      return 'access was denied';
    }

    if (error.osError.errorCode == 32) {
      return 'it was in use by another process';
    }

    if (error.osError.errorCode == 145) {
      return 'of dart-lang/sdk#25353';
    }

    return null;
  }

  for (var i = 0; i < 2; i++) {
    try {
      operation();
      return;
    } on FileSystemException catch (error) {
      var reason = getErrorReason(error);
      if (reason == null) rethrow;

      log.io('Failed to $description because $reason. '
          'Retrying in 50ms.');
      sleep(Duration(milliseconds: 50));
    }
  }

  try {
    operation();
  } on FileSystemException catch (error) {
    var reason = getErrorReason(error);
    if (reason == null) rethrow;

    fail('Failed to $description because $reason.\n'
        'This may be caused by a virus scanner or having a file\n'
        'in the directory open in another application.');
  }
}

/// Deletes whatever's at [path], whether it's a file, directory, or symlink.
///
/// If it's a directory, it will be deleted recursively.
void deleteEntry(String path) {
  _attempt('delete entry', () {
    if (linkExists(path)) {
      log.io('Deleting link $path.');
      Link(path).deleteSync();
    } else if (dirExists(path)) {
      log.io('Deleting directory $path.');
      Directory(path).deleteSync(recursive: true);
    } else if (fileExists(path)) {
      log.io('Deleting file $path.');
      File(path).deleteSync();
    }
  });
}

/// Attempts to delete whatever's at [path], but doesn't throw an exception if
/// the deletion fails.
void tryDeleteEntry(String path) {
  try {
    deleteEntry(path);
  } catch (error, stackTrace) {
    log.fine('Failed to delete $path: $error\n'
        '${Chain.forTrace(stackTrace)}');
  }
}

/// "Cleans" [dir].
///
/// If that directory already exists, it is deleted. Then a new empty directory
/// is created.
void cleanDir(String dir) {
  if (entryExists(dir)) deleteEntry(dir);
  ensureDir(dir);
}

/// Renames (i.e. moves) the directory [from] to [to].
void renameDir(String from, String to) {
  _attempt('rename directory', () {
    log.io('Renaming directory $from to $to.');
    try {
      Directory(from).renameSync(to);
    } on IOException {
      // Ensure that [to] isn't left in an inconsistent state. See issue 12436.
      if (entryExists(to)) deleteEntry(to);
      rethrow;
    }
  });
}

/// Creates a new symlink at path [symlink] that points to [target].
///
/// Returns a [Future] which completes to the path to the symlink file.
///
/// If [relative] is true, creates a symlink with a relative path from the
/// symlink to the target. Otherwise, uses the [target] path unmodified.
///
/// Note that on Windows, only directories may be symlinked to.
void createSymlink(String target, String symlink, {bool relative = false}) {
  if (relative) {
    // Relative junction points are not supported on Windows. Instead, just
    // make sure we have a clean absolute path because it will interpret a
    // relative path to be relative to the cwd, not the symlink, and will be
    // confused by forward slashes.
    if (Platform.isWindows) {
      target = path.normalize(path.absolute(target));
    } else {
      // If the directory where we're creating the symlink was itself reached
      // by traversing a symlink, we want the relative path to be relative to
      // it's actual location, not the one we went through to get to it.
      var symlinkDir = canonicalize(path.dirname(symlink));
      target = path.normalize(path.relative(target, from: symlinkDir));
    }
  }

  log.fine('Creating $symlink pointing to $target');
  Link(symlink).createSync(target);
}

/// Creates a new symlink that creates an alias at [symlink] that points to the
/// `lib` directory of package [target].
///
/// If [target] does not have a `lib` directory, this shows a warning if
/// appropriate and then does nothing.
///
/// If [relative] is true, creates a symlink with a relative path from the
/// symlink to the target. Otherwise, uses the [target] path unmodified.
void createPackageSymlink(String name, String target, String symlink,
    {bool isSelfLink = false, bool relative = false}) {
  // See if the package has a "lib" directory. If not, there's nothing to
  // symlink to.
  target = path.join(target, 'lib');
  if (!dirExists(target)) return;

  log.fine("Creating ${isSelfLink ? "self" : ""}link for package '$name'.");
  createSymlink(target, symlink, relative: relative);
}

/// Whether the current process is one of pub's test files.
///
/// This works because an actual pub executable that imports this will always
/// start with "pub".
final bool runningAsTest =
    !path.url.basename(Platform.script.path).startsWith('pub.');

// TODO(nweiz): Use the test API when test#48 is fixed.
/// Whether the current process is one of pub's test files being run through the
/// test package's test runner.
///
/// The test runner starts all tests from a `data:` URI.
final bool _runningAsTestRunner = Platform.script.scheme == 'data';

/// Whether the current process is a pub subprocess being run from a test.
///
/// The "_PUB_TESTING" variable is automatically set for all the test code's
/// invocations of pub.
final bool runningFromTest = Platform.environment.containsKey('_PUB_TESTING');

/// Whether pub is running from within the Dart SDK, as opposed to from the Dart
/// source repository.
final bool _runningFromSdk =
    !runningFromTest && Platform.script.path.endsWith('.snapshot');

/// A regular expression to match the script path of a pub script running from
/// source in the Dart repo.
final _dartRepoRegExp = RegExp(r'/third_party/pkg/pub/('
    r'bin/pub\.dart'
    r'|'
    r'test/.*_test\.dart'
    r')$');

/// Whether pub is running from source in the Dart repo.
///
/// This can happen when running tests against the repo, as well as when
/// building Observatory.
final bool runningFromDartRepo = (() {
  if (_runningAsTestRunner) {
    // When running from the test runner, we can't find our location via
    // Platform.script since the runner munges that. However, it guarantees that
    // the working directory is <repo>/third_party/pkg/pub.
    return path.current.contains(RegExp(r'[/\\]third_party[/\\]pkg[/\\]pub$'));
  } else {
    return Platform.script.path.contains(_dartRepoRegExp);
  }
})();

/// Resolves [target] relative to the Dart SDK's `asset` directory.
///
/// Throws a [StateError] if called from within the Dart repo.
String _sdkAssetPath(String target) {
  if (runningFromDartRepo) {
    throw StateError("Can't get SDK assets from within the Dart repo.");
  }

  return path.join(
      sdk.rootDirectory, 'lib', '_internal', 'pub', 'asset', target);
}

/// The path to the root of pub's sources in the pub repo.
///
/// This throws a [StateError] if it's called when running pub from the SDK.
final String pubRoot = (() {
  if (_runningFromSdk) {
    throw StateError("Can't get pub's root from the SDK.");
  }

  // The test runner always runs from the working directory.
  if (_runningAsTestRunner) return path.current;

  var script = path.fromUri(Platform.script);
  if (runningAsTest) {
    // Running from "test/../some_test.dart".
    var components = path.split(script);
    var testIndex = components.indexOf('test');
    if (testIndex == -1) throw StateError("Can't find pub's root.");
    return path.joinAll(components.take(testIndex));
  }

  // Pub is run from "bin/pub.dart".
  return path.dirname(path.dirname(script));
})();

/// The path to the root of the Dart repo.
///
/// This throws a [StateError] if it's called when not running pub from source
/// in the Dart repo.
final String dartRepoRoot = (() {
  if (!runningFromDartRepo) {
    throw StateError('Not running from source in the Dart repo.');
  }

  if (_runningAsTestRunner) {
    // When running in test code started by the test runner, the working
    // directory will always be <repo>/third_party/pkg/pub.
    return path.dirname(path.dirname(path.dirname(path.current)));
  }

  // Get the URL of the repo root in a way that works when either both running
  // as a test or as a pub executable.
  var url = Platform.script
      .replace(path: Platform.script.path.replaceAll(_dartRepoRegExp, ''));
  return path.fromUri(url);
})();

/// A line-by-line stream of standard input.
final Stream<String> _stdinLines =
    ByteStream(stdin).toStringStream().transform(const LineSplitter());

/// Displays a message and reads a yes/no confirmation from the user.
///
/// Returns a [Future] that completes to `true` if the user confirms or `false`
/// if they do not.
///
/// This will automatically append " (y/N)?" to the message, so [message]
/// should just be a fragment like, "Are you sure you want to proceed". The
/// default for an empty response, or any response not starting with `y` or `Y`
/// is false.
Future<bool> confirm(String message) {
  log.fine('Showing confirm message: $message');
  if (runningFromTest) {
    log.message('$message (y/N)?');
  } else {
    stdout.write(log.format('$message (y/N)? '));
  }
  return _stdinLines.first.then(RegExp(r'^[yY]').hasMatch);
}

/// Flushes the stdout and stderr streams, then exits the program with the given
/// status code.
///
/// This returns a Future that will never complete, since the program will have
/// exited already. This is useful to prevent Future chains from proceeding
/// after you've decided to exit.
Future flushThenExit(int status) {
  return Future.wait([stdout.close(), stderr.close()])
      .then((_) => exit(status));
}

/// Returns a [EventSink] that pipes all data to [consumer] and a [Future] that
/// will succeed when [EventSink] is closed or fail with any errors that occur
/// while writing.
Pair<EventSink<T>, Future> _consumerToSink<T>(StreamConsumer<T> consumer) {
  var controller = StreamController<T>(sync: true);
  var done = controller.stream.pipe(consumer);
  return Pair(controller.sink, done);
}

/// Spawns and runs the process located at [executable], passing in [args].
///
/// Returns a [Future] that will complete with the results of the process after
/// it has ended.
///
/// The spawned process will inherit its parent's environment variables. If
/// [environment] is provided, that will be used to augment (not replace) the
/// the inherited variables.
Future<PubProcessResult> runProcess(String executable, List<String> args,
    {workingDir, Map<String, String> environment, bool runInShell = false}) {
  ArgumentError.checkNotNull(executable, 'executable');

  return _descriptorPool.withResource(() async {
    var result = await _doProcess(Process.run, executable, args,
        workingDir: workingDir,
        environment: environment,
        runInShell: runInShell);

    var pubResult =
        PubProcessResult(result.stdout, result.stderr, result.exitCode);
    log.processResult(executable, pubResult);
    return pubResult;
  });
}

/// Spawns the process located at [executable], passing in [args].
///
/// Returns a [Future] that will complete with the [Process] once it's been
/// started.
///
/// The spawned process will inherit its parent's environment variables. If
/// [environment] is provided, that will be used to augment (not replace) the
/// the inherited variables.
Future<_PubProcess> _startProcess(String executable, List<String> args,
    {workingDir, Map<String, String> environment, bool runInShell = false}) {
  return _descriptorPool.request().then((resource) async {
    var ioProcess = await _doProcess(Process.start, executable, args,
        workingDir: workingDir,
        environment: environment,
        runInShell: runInShell);

    var process = _PubProcess(ioProcess);
    unawaited(process.exitCode.whenComplete(resource.release));
    return process;
  });
}

/// Like [runProcess], but synchronous.
PubProcessResult runProcessSync(String executable, List<String> args,
    {String workingDir,
    Map<String, String> environment,
    bool runInShell = false}) {
  ArgumentError.checkNotNull(executable, 'executable');

  var result = _doProcess(Process.runSync, executable, args,
      workingDir: workingDir, environment: environment, runInShell: runInShell);
  var pubResult =
      PubProcessResult(result.stdout, result.stderr, result.exitCode);
  log.processResult(executable, pubResult);
  return pubResult;
}

/// A wrapper around [Process] that exposes `dart:async`-style APIs.
class _PubProcess {
  /// The underlying `dart:io` [Process].
  final Process _process;

  /// The mutable field for [stdin].
  EventSink<List<int>> _stdin;

  /// The mutable field for [stdinClosed].
  Future _stdinClosed;

  /// The mutable field for [stdout].
  ByteStream _stdout;

  /// The mutable field for [stderr].
  ByteStream _stderr;

  /// The mutable field for [exitCode].
  Future<int> _exitCode;

  /// The sink used for passing data to the process's standard input stream.
  ///
  /// Errors on this stream are surfaced through [stdinClosed], [stdout],
  /// [stderr], and [exitCode], which are all members of an [ErrorGroup].
  EventSink<List<int>> get stdin => _stdin;

  // TODO(nweiz): write some more sophisticated Future machinery so that this
  // doesn't surface errors from the other streams/futures, but still passes its
  // unhandled errors to them. Right now it's impossible to recover from a stdin
  // error and continue interacting with the process.
  /// A [Future] that completes when [stdin] is closed, either by the user or by
  /// the process itself.
  ///
  /// This is in an [ErrorGroup] with [stdout], [stderr], and [exitCode], so any
  /// error in process will be passed to it, but won't reach the top-level error
  /// handler unless nothing has handled it.
  Future get stdinClosed => _stdinClosed;

  /// The process's standard output stream.
  ///
  /// This is in an [ErrorGroup] with [stdinClosed], [stderr], and [exitCode],
  /// so any error in process will be passed to it, but won't reach the
  /// top-level error handler unless nothing has handled it.
  ByteStream get stdout => _stdout;

  /// The process's standard error stream.
  ///
  /// This is in an [ErrorGroup] with [stdinClosed], [stdout], and [exitCode],
  /// so any error in process will be passed to it, but won't reach the
  /// top-level error handler unless nothing has handled it.
  ByteStream get stderr => _stderr;

  /// A [Future] that will complete to the process's exit code once the process
  /// has finished running.
  ///
  /// This is in an [ErrorGroup] with [stdinClosed], [stdout], and [stderr], so
  /// any error in process will be passed to it, but won't reach the top-level
  /// error handler unless nothing has handled it.
  Future<int> get exitCode => _exitCode;

  /// Creates a new [_PubProcess] wrapping [process].
  _PubProcess(Process process) : _process = process {
    var errorGroup = ErrorGroup();

    var pair = _consumerToSink(process.stdin);
    _stdin = pair.first;
    _stdinClosed = errorGroup.registerFuture(pair.last);

    _stdout = ByteStream(errorGroup.registerStream(process.stdout));
    _stderr = ByteStream(errorGroup.registerStream(process.stderr));

    var exitCodeCompleter = Completer<int>();
    _exitCode = errorGroup.registerFuture(exitCodeCompleter.future);
    _process.exitCode.then((code) => exitCodeCompleter.complete(code));
  }

  /// Sends [signal] to the underlying process.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}

/// Calls [fn] with appropriately modified arguments.
///
/// [fn] should have the same signature as [Process.start], except that the
/// returned value may have any return type.
T _doProcess<T>(
    T Function(String, List<String>,
            {String workingDirectory,
            Map<String, String> environment,
            bool runInShell})
        fn,
    String executable,
    List<String> args,
    {String workingDir,
    Map<String, String> environment,
    bool runInShell = false}) {
  // TODO(rnystrom): Should dart:io just handle this?
  // Spawning a process on Windows will not look for the executable in the
  // system path. So, if executable looks like it needs that (i.e. it doesn't
  // have any path separators in it), then spawn it through a shell.
  if (Platform.isWindows && !executable.contains('\\')) {
    args = ['/c', executable, ...args];
    executable = 'cmd';
  }

  log.process(executable, args, workingDir ?? '.');

  return fn(executable, args,
      workingDirectory: workingDir,
      environment: environment,
      runInShell: runInShell);
}

/// Updates [path]'s modification time.
void touch(String path) => File(path).setLastModifiedSync(DateTime.now());

/// Creates a temporary directory and passes its path to [fn].
///
/// Once the [Future] returned by [fn] completes, the temporary directory and
/// all its contents are deleted. [fn] can also return `null`, in which case
/// the temporary directory is deleted immediately afterwards.
///
/// Returns a future that completes to the value that the future returned from
/// [fn] completes to.
Future<T> withTempDir<T>(FutureOr<T> Function(String path) fn) async {
  var tempDir = await _createSystemTempDir();
  try {
    return await fn(tempDir);
  } finally {
    deleteEntry(tempDir);
  }
}

/// Binds an [HttpServer] to [host] and [port].
///
/// If [host] is "localhost", this will automatically listen on both the IPv4
/// and IPv6 loopback addresses.
Future<HttpServer> bindServer(String host, int port) async {
  var server = host == 'localhost'
      ? await HttpMultiServer.loopback(port)
      : await HttpServer.bind(host, port);
  server.autoCompress = true;
  return server;
}

String _tarPath = _findTarPath();

/// Find a tar. Prefering system installed tar.
///
/// On linux tar should always be /bin/tar [See FHS 2.3][1]
/// On MacOS it seems to always be /usr/bin/tar.
///
/// [1]: https://refspecs.linuxfoundation.org/FHS_2.3/fhs-2.3.pdf
String _findTarPath() {
  for (final file in ['/bin/tar', '/usr/bin/tar']) {
    if (fileExists(file)) {
      return file;
    }
  }
  log.warning(
      'Could not find a system `tar` installed in /bin/tar or /usr/bin/tar, '
      'attempting to use tar from PATH');
  return 'tar';
}

/// Extracts a `.tar.gz` file from [stream] to [destination].
Future extractTarGz(Stream<List<int>> stream, String destination) async {
  log.fine('Extracting .tar.gz stream to $destination.');
  final decompressed = stream.transform(GZipCodec().decoder);

  // We used to stream directly to `tar`,  but that was fragile in certain
  // settings.
  final processResult = await withTempDir((tempDir) async {
    final tarFile = path.join(tempDir, 'archive.tar');
    try {
      await _createFileFromStream(decompressed, tarFile);
    } catch (e) {
      // We don't know the error type here: https://dartbug.com/41270
      throw FileSystemException('Could not decompress gz stream $e');
    }
    return (Platform.isWindows)
        ? runProcess(_pathTo7zip, ['x', tarFile], workingDir: destination)
        : runProcess(_tarPath, [
            if (_noUnknownKeyword) '--warning=no-unknown-keyword',
            '--extract',
            '--no-same-owner',
            '--no-same-permissions',
            '--directory',
            destination,
            '--file',
            tarFile,
          ]);
  });
  if (processResult.exitCode != exit_codes.SUCCESS) {
    throw FileSystemException(
        'Could not un-tar (exit code ${processResult.exitCode}). Error:\n'
        '${processResult.stdout.join("\n")}\n'
        '${processResult.stderr.join("\n")}');
  }
  log.fine('Extracted .tar.gz to $destination. Exit code $exitCode.');
}

/// Whether to include "--warning=no-unknown-keyword" when invoking tar.
///
/// BSD tar (the default on OS X) can insert strange headers to a tarfile that
/// GNU tar (the default on Linux) is unable to understand. This will cause GNU
/// tar to emit a number of harmless but scary-looking warnings which are
/// silenced by this flag.
final bool _noUnknownKeyword = _computeNoUnknownKeyword();
bool _computeNoUnknownKeyword() {
  if (!Platform.isLinux) return false;
  var result = Process.runSync(_tarPath, ['--version']);
  if (result.exitCode != 0) {
    throw ApplicationException(
        'Failed to run tar (exit code ${result.exitCode}):\n${result.stderr}');
  }

  var match =
      RegExp(r'^tar \(GNU tar\) (\d+).(\d+)\n').firstMatch(result.stdout);
  if (match == null) return false;

  var major = int.parse(match[1]);
  var minor = int.parse(match[2]);
  return major >= 2 || (major == 1 && minor >= 23);
}

final String _pathTo7zip = (() {
  if (!runningFromDartRepo) return _sdkAssetPath(path.join('7zip', '7za.exe'));
  return path.join(dartRepoRoot, 'third_party', '7zip', '7za.exe');
})();

/// Create a .tar.gz archive from a list of entries.
///
/// Each entry can be a [String], [Directory], or [File] object. The root of
/// the archive is considered to be [baseDir], which defaults to the current
/// working directory.
///
/// Returns a [ByteStream] that emits the contents of the archive.
ByteStream createTarGz(List<String> contents, {String baseDir}) {
  return ByteStream(StreamCompleter.fromFuture(Future.sync(() async {
    var buffer = StringBuffer();
    buffer.write('Creating .tar.gz stream containing:\n');
    contents.forEach(buffer.writeln);
    log.fine(buffer.toString());

    baseDir ??= path.current;
    baseDir = path.absolute(baseDir);
    contents = contents.map((entry) {
      entry = path.absolute(entry);
      if (!path.isWithin(baseDir, entry)) {
        throw ArgumentError('Entry $entry is not inside $baseDir.');
      }
      return path.relative(entry, from: baseDir);
    }).toList();

    if (!Platform.isWindows) {
      var args = [
        // ustar is the most recent tar format that's compatible across all
        // OSes.
        '--format=ustar',
        '--create',
        '--gzip',
        '--directory',
        baseDir
      ];

      String stdin;
      if (Platform.isLinux) {
        // GNU tar flags.
        // https://www.gnu.org/software/tar/manual/html_section/tar_33.html

        args.addAll(['--files-from', '/dev/stdin']);
        stdin = contents.join('\n');

        /// Travis's version of tar apparently doesn't support passing unknown
        /// values to the --owner and --group flags for some reason.
        if (!isTravis) {
          // The ustar format doesn't support large UIDs. We don't care about
          // preserving ownership anyway, so we just set them to "pub".
          args.addAll(['--owner=pub', '--group=pub']);
        }
      } else {
        // OSX can take inputs in mtree format since at least OSX 10.9 (bsdtar
        // 2.8.3). We use this to set the uname and gname, since it doesn't have
        // flags for those.
        //
        // https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man1/tar.1.html
        args.add('@/dev/stdin');

        // The ustar format doesn't support large UIDs. We don't care about
        // preserving ownership anyway, so we just set them to "pub".
        // TODO(rnystrom): This assumes contents does not contain any
        // directories.
        var mtreeHeader = '#mtree\n/set uname=pub gname=pub type=file\n';

        // We need a newline at the end, otherwise the last file would get
        // ignored.
        stdin =
            mtreeHeader + contents.join('\n').replaceAll(' ', r'\040') + '\n';
      }

      // Setting the working directory should be unnecessary since we pass an
      // explicit base directory to tar. However, on Mac when using an mtree
      // input file, relative paths in the mtree file are interpreted as
      // relative to the current working directory, not the "--directory"
      // argument.
      var process = await _startProcess(_tarPath, args, workingDir: baseDir);
      process.stdin.add(utf8.encode(stdin));
      process.stdin.close();
      return process.stdout;
    }

    // Don't use [withTempDir] here because we don't want to delete the temp
    // directory until the returned stream has closed.
    var tempDir = await _createSystemTempDir();

    try {
      // Create the file containing the list of files to compress.
      var contentsPath = path.join(tempDir, 'files.txt');
      writeTextFile(contentsPath, contents.join('\n'));

      // Create the tar file.
      var tarFile = path.join(tempDir, 'intermediate.tar');
      var args = ['a', '-w$baseDir', tarFile, '@$contentsPath'];

      // We're passing 'baseDir' both as '-w' and setting it as the working
      // directory explicitly here intentionally. The former ensures that the
      // files added to the archive have the correct relative path in the
      // archive. The latter enables relative paths in the "-i" args to be
      // resolved.
      await runProcess(_pathTo7zip, args, workingDir: baseDir);

      // GZIP it. 7zip doesn't support doing both as a single operation.
      // Send the output to stdout.
      args = ['a', 'unused', '-tgzip', '-so', tarFile];
      return (await _startProcess(_pathTo7zip, args))
          .stdout
          .transform(onDoneTransformer(() => deleteEntry(tempDir)));
    } catch (_) {
      deleteEntry(tempDir);
      rethrow;
    }
  })));
}

/// Contains the results of invoking a [Process] and waiting for it to complete.
class PubProcessResult {
  final List<String> stdout;
  final List<String> stderr;
  final int exitCode;

  PubProcessResult(String stdout, String stderr, this.exitCode)
      : stdout = _toLines(stdout),
        stderr = _toLines(stderr);

  // TODO(rnystrom): Remove this and change to returning one string.
  static List<String> _toLines(String output) {
    var lines = splitLines(output);
    if (lines.isNotEmpty && lines.last == '') lines.removeLast();
    return lines;
  }

  bool get success => exitCode == exit_codes.SUCCESS;
}
