// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helper functionality to make working with IO easier.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:cli_util/cli_util.dart'
    show EnvironmentNotFoundException, applicationConfigHome;
import 'package:collection/collection.dart';
import 'package:http/http.dart' show ByteStream;
import 'package:http_multi_server/http_multi_server.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:tar/tar.dart';

import 'error_group.dart';
import 'exceptions.dart';
import 'exit_codes.dart' as exit_codes;
import 'log.dart' as log;
import 'utils.dart';

export 'package:http/http.dart' show ByteStream;

/// Environment variable names that are recognized by pub.
class EnvironmentKeys {
  /// Overrides terminal detection for stdout.
  ///
  /// Supported values:
  /// * missing or `''` (empty string): dart:io terminal detection is used.
  /// * `"0"`: output as if no terminal is attached
  ///   - no animations
  ///   - no ANSI colors
  ///   - use unicode characters
  ///   - silent inside [log.errorsOnlyUnlessTerminal]).
  /// * `"1"`: output as if a terminal is attached
  ///   - animations
  ///   - ANSI colors (can be overriden again with NO_COLOR)
  ///   - no unicode on Windows
  ///   - normal verbosity in output inside
  ///   [log.errorsOnlyUnlessTerminal]).
  ///
  /// This variable is mainly for testing, and no forward compatibility
  /// guarantees are given.
  static const forceTerminalOutput = '_PUB_FORCE_TERMINAL_OUTPUT';
  // TODO(sigurdm): Add other environment keys here.
}

/// The pool used for restricting access to asynchronous operations that consume
/// file descriptors.
///
/// The maximum number of allocated descriptors is based on empirical tests that
/// indicate that beyond 32, additional file reads don't provide substantial
/// additional throughput.
final _descriptorPool = Pool(32);

/// The assumed default file mode on Linux and macOS
const _defaultMode = 420; // 644₈

/// Mask for executable bits in file modes.
const _executableMask = 0x49; // 001 001 001

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

/// Stats [path], assuming it or the entry it is a link to is a file.
///
/// Returns `null` if it is not a file (eg. a directory or not existing).
FileStat? tryStatFile(String path) {
  var stat = File(path).statSync();
  if (stat.type == FileSystemEntityType.link) {
    stat = File(File(path).resolveSymbolicLinksSync()).statSync();
  }
  if (stat.type == FileSystemEntityType.file) {
    return stat;
  }
  return null;
}

FileStat statPath(String path) {
  return File(path).statSync();
}

/// Returns the canonical path for [pathString].
///
/// This is the normalized, absolute path, with symlinks resolved. Broken or
/// recursive symlinks will not be fully resolved.
///
/// This doesn't require [pathString] to point to a path that exists on the
/// filesystem; nonexistent or unreadable path entries are treated as normal
/// directories.
String canonicalize(String pathString) {
  final seen = <String>{};
  var components = Queue<String>.from(
    p.split(p.normalize(p.absolute(pathString))),
  );

  // The canonical path, built incrementally as we iterate through [components].
  var newPath = components.removeFirst();

  // Move through the components of the path, resolving each one's symlinks as
  // necessary. A resolved component may also add new components that need to be
  // resolved in turn.
  while (components.isNotEmpty) {
    seen.add(p.join(newPath, p.joinAll(components)));
    final resolvedPath = _resolveLink(
      p.join(newPath, components.removeFirst()),
    );
    final relative = p.relative(resolvedPath, from: newPath);

    // If the resolved path of the component relative to `newPath` is just ".",
    // that means component was a symlink pointing to its parent directory. We
    // can safely ignore such components.
    if (relative == '.') continue;

    final relativeComponents = Queue<String>.from(p.split(relative));

    // If the resolved path is absolute relative to `newPath`, that means it's
    // on a different drive. We need to canonicalize the entire target of that
    // symlink again.
    if (p.isAbsolute(relative)) {
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
    while (relativeComponents.firstOrNull == '..') {
      newPath = p.dirname(newPath);
      relativeComponents.removeFirst();
    }

    // If there's only one component left, [resolveLink] guarantees that it's
    // not a link (or is a broken link). We can just add it to `newPath` and
    // continue resolving the remaining components.
    if (relativeComponents.length == 1) {
      newPath = p.join(newPath, relativeComponents.single);
      continue;
    }

    // If we've already tried to canonicalize the new path, we've encountered a
    // symlink loop. Avoid going infinite by treating the recursive symlink as
    // the canonical path.
    final newSubPath = p.join(newPath, p.joinAll(relativeComponents));
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
  final seen = <String>{};
  while (linkExists(link) && seen.add(link)) {
    link = p.normalize(p.join(p.dirname(link), Link(link).targetSync()));
  }
  return link;
}

/// Reads the contents of the text file at [path].
String readTextFile(String path) => File(path).readAsStringSync();

/// Reads the contents of the text file at [path].
/// Returns `null` if the operation fails.
String? tryReadTextFile(String path) {
  try {
    return readTextFile(path);
  } on FileSystemException {
    // TODO: Consider handlind file-not-found differently from other exceptions.
    return null;
  }
}

/// Reads the contents of the text file [file].
Future<String> readTextFileAsync(String file) {
  return _descriptorPool.withResource(() => File(file).readAsString());
}

/// Reads the contents of the binary file [file].
Uint8List readBinaryFile(String file) {
  log.io('Reading binary file $file.');
  final contents = File(file).readAsBytesSync();
  log.io('Read ${contents.length} bytes from $file.');
  return contents;
}

/// Reads the contents of the binary file [file] as a [Stream].
Stream<List<int>> readBinaryFileAsStream(String file) {
  log.io('Reading binary file $file.');
  final contents = File(file).openRead();
  return contents;
}

/// Creates [file] and writes [contents] to it.
///
/// If [dontLogContents] is `true`, the contents of the file will never be
/// logged.
void writeTextFile(
  String file,
  String contents, {
  bool dontLogContents = false,
  Encoding encoding = utf8,
}) {
  // Sanity check: don't spew a huge file.
  log.io('Writing ${contents.length} characters to text file $file.');
  if (!dontLogContents && contents.length < 1024 * 1024) {
    log.fine('Contents:\n$contents');
  }

  deleteIfLink(file);
  File(file).writeAsStringSync(contents, encoding: encoding);
}

/// Reads the file at [path] and writes [newContent] to it, if it is different
/// from [newContent].
///
/// If the file doesn't exist it is always written.
void writeTextFileIfDifferent(String path, String newContent) {
  // Compare to the present package_config.json
  // For purposes of equality we don't care about the `generated` timestamp.
  final originalText = tryReadTextFile(path);
  if (originalText != newContent) {
    writeTextFile(path, newContent);
  } else {
    log.fine('`$path` is unchanged. Not rewriting.');
  }
}

/// Reads the contents of the binary file [file].
void writeBinaryFile(String file, Uint8List data) {
  log.io('Writing ${data.length} bytes to file $file.');
  File(file).writeAsBytesSync(data);
}

/// Creates [file] and writes [contents] to it.
///
/// If [dontLogContents] is `true`, the contents of the file will never be
/// logged.
Future<void> writeTextFileAsync(
  String file,
  String contents, {
  bool dontLogContents = false,
  Encoding encoding = utf8,
}) async {
  // Sanity check: don't spew a huge file.
  log.io('Writing ${contents.length} characters to text file $file.');
  if (!dontLogContents && contents.length < 1024 * 1024) {
    log.fine('Contents:\n$contents');
  }

  deleteIfLink(file);
  await File(file).writeAsString(contents, encoding: encoding);
}

/// Writes [stream] to a new file at path [file].
///
/// Replaces any file already at that path. Completes when the file is done
/// being written.
Future<String> createFileFromStream(Stream<List<int>> stream, String file) {
  // TODO(nweiz): remove extra logging when we figure out the windows bot issue.
  log.io('Creating $file from stream.');

  return _descriptorPool.withResource(() async {
    deleteIfLink(file);
    await stream.pipe(File(file).openWrite());
    log.fine('Created $file from stream.');
    return file;
  });
}

void _chmod(int mode, String file) {
  runProcessSync('chmod', [mode.toRadixString(8), file]);
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

/// Creates a temp directory in [base], whose name will be [prefix] with
/// characters appended to it to make a unique name.
///
/// Returns the path of the created directory.
String createTempDir(String base, String prefix) {
  final tempDir = Directory(base).createTempSync(prefix);
  log.io('Created temp directory ${tempDir.path}');
  return tempDir.path;
}

/// Creates a temp directory in the system temp directory, whose name will be
/// 'pub_' with characters appended to it to make a unique name.
///
/// Returns the path of the created directory.
Future<String> _createSystemTempDir() async {
  final tempDir = await Directory.systemTemp.createTemp('pub_');
  log.io('Created temp directory ${tempDir.path}');
  return tempDir.resolveSymbolicLinksSync();
}

String resolveSymlinksOfDir(String dir) {
  return Directory(dir).resolveSymbolicLinksSync();
}

/// Lists the contents of [dir].
///
/// If [recursive] is `true`, lists subdirectory contents (defaults to `false`).
/// If [includeHidden] is `true`, includes files and directories beginning with
/// `.` (defaults to `false`). If [includeDirs] is `true`, includes directories
/// as well as files (defaults to `true`).
///
/// [allowed] is a list of hidden filenames to include even when
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
List<String> listDir(
  String dir, {
  bool recursive = false,
  bool includeHidden = false,
  bool includeDirs = true,
  Iterable<String> allowed = const <String>[],
}) {
  final allowListFilter = createFileFilter(allowed);

  // This is used in some performance-sensitive paths and can list many, many
  // files. As such, it leans more heavily towards optimization as opposed to
  // readability than most code in pub. In particular, it avoids using the path
  // package, since re-parsing a path is very expensive relative to string
  // operations.
  return Directory(dir)
      .listSync(recursive: recursive)
      .where((entity) {
        if (!includeDirs && entity is Directory) return false;
        if (entity is Link) return false;
        if (includeHidden) return true;

        // Using substring here is generally problematic in cases where dir has
        // one or more trailing slashes. If you do listDir("foo"), you'll get
        // back paths like "foo/bar". If you do listDir("foo/"), you'll get
        // "foo/bar" (note the trailing slash was dropped. If you do
        // listDir("foo//"), you'll get "foo//bar".
        //
        // This means if you strip off the prefix, the resulting string may have
        // a leading separator (if the prefix did not have a trailing one) or it
        // may not. However, since we are only using the results of that to call
        // contains() on, the leading separator is harmless.
        assert(entity.path.startsWith(dir));
        var pathInDir = entity.path.substring(dir.length);

        // If the basename is in [allowed], don't count its "/." as making the
        // file hidden.

        if (allowListFilter.any(pathInDir.contains)) {
          final allowedBasename = allowListFilter.firstWhere(
            pathInDir.contains,
          );
          pathInDir = pathInDir.substring(
            0,
            pathInDir.length - allowedBasename.length,
          );
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
///
/// For some operations it makes sense to handle ERROR_DIR_NOT_EMPTY
/// differently. They can pass [ignoreEmptyDir] = `true`.
void _attempt(
  String description,
  void Function() operation, {
  bool ignoreEmptyDir = false,
}) {
  if (!Platform.isWindows) {
    operation();
    return;
  }

  String? getErrorReason(FileSystemException error) {
    // ERROR_ACCESS_DENIED
    if (error.osError?.errorCode == 5) {
      return 'access was denied';
    }

    // ERROR_SHARING_VIOLATION
    if (error.osError?.errorCode == 32) {
      return 'it was in use by another process';
    }

    // ERROR_DIR_NOT_EMPTY
    if (!ignoreEmptyDir && _isDirectoryNotEmptyException(error)) {
      return 'of dart-lang/sdk#25353';
    }

    return null;
  }

  const maxRetries = 50;
  for (var i = 0; i < maxRetries; i++) {
    try {
      operation();
      break;
    } on FileSystemException catch (error) {
      final reason = getErrorReason(error);
      if (reason == null) rethrow;

      if (i < maxRetries - 1) {
        log.io(
          'Pub failed to $description because $reason. '
          'Retrying in 50ms.',
        );
        sleep(const Duration(milliseconds: 50));
      } else {
        fail(
          'Pub failed to $description because $reason.\n'
          'This may be caused by a virus scanner or having a file\n'
          'in the directory open in another application.',
        );
      }
    }
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
    log.fine(
      'Pub failed to delete $path: $error\n'
      '${Chain.forTrace(stackTrace)}',
    );
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
    Directory(from).renameSync(to);
  }, ignoreEmptyDir: true);
}

/// Renames directory [from] to [to].
/// If it fails with "destination not empty" we log and continue, assuming
/// another process got there before us.
void tryRenameDir(String from, String to) {
  ensureDir(p.dirname(to));
  try {
    renameDir(from, to);
  } on FileSystemException catch (e) {
    tryDeleteEntry(from);
    if (!_isDirectoryNotEmptyException(e)) {
      rethrow;
    }
    log.fine('''
Destination directory $to already existed.
Assuming a concurrent pub invocation installed it.''');
  }
}

void copyFile(String from, String to) {
  log.io('Copying "$from" to "$to".');
  File(from).copySync(to);
}

void renameFile(String from, String to) {
  log.io('Renaming "$from" to "$to".');
  _attempt('Renaming `$from` to `$to`', () {
    File(from).renameSync(to);
  });
}

bool _isDirectoryNotEmptyException(FileSystemException e) {
  final errorCode = e.osError?.errorCode;
  return
  // On Linux rename will fail with either ENOTEMPTY or EEXISTS if directory
  // exists: https://man7.org/linux/man-pages/man2/rename.2.html
  // ```
  // #define  ENOTEMPTY 39  /* Directory not empty */
  // #define  EEXIST    17  /* File exists */
  // ```
  // https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/asm-generic/errno-base.h#n21
  // https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/asm-generic/errno.h#n20
  (Platform.isLinux && (errorCode == 39 || errorCode == 17)) ||
      // On Windows this may fail with ERROR_DIR_NOT_EMPTY or
      // ERROR_ALREADY_EXISTS
      // https://docs.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-
      (Platform.isWindows && (errorCode == 145 || errorCode == 183)) ||
      // On MacOS rename will fail with ENOTEMPTY if directory exists.
      // We also catch EEXIST - perhaps that could also be thrown...
      // ```
      // #define ENOTEMPTY       66              /* Directory not empty */
      // #define	EEXIST		17	/* File exists */
      // ```
      // https://github.com/apple-oss-distributions/xnu/blob/bb611c8fecc755a0d8e56e2fa51513527c5b7a0e/bsd/sys/errno.h#L190
      (Platform.isMacOS && (errorCode == 66 || errorCode == 17));
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
      target = p.normalize(p.absolute(target));
    } else {
      // If the directory where we're creating the symlink was itself reached
      // by traversing a symlink, we want the relative path to be relative to
      // it's actual location, not the one we went through to get to it.
      final symlinkDir = canonicalize(p.dirname(symlink));
      target = p.normalize(p.relative(target, from: symlinkDir));
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
void createPackageSymlink(
  String name,
  String target,
  String symlink, {
  bool isSelfLink = false,
  bool relative = false,
}) {
  // See if the package has a "lib" directory. If not, there's nothing to
  // symlink to.
  target = p.join(target, 'lib');
  if (!dirExists(target)) return;

  log.fine("Creating ${isSelfLink ? "self" : ""}link for package '$name'.");
  createSymlink(target, symlink, relative: relative);
}

/// Whether the current process is a pub subprocess being run from a test.
///
/// The "_PUB_TESTING" variable is automatically set for all the test code's
/// invocations of pub.
final bool runningFromTest =
    Platform.environment.containsKey('_PUB_TESTING') && _assertionsEnabled;

final bool _assertionsEnabled = () {
  try {
    assert(false);
    // ignore: avoid_catching_errors
  } on AssertionError {
    return true;
  }
  return false;
}();

final bool runningFromFlutter =
    Platform.environment.containsKey('PUB_ENVIRONMENT') &&
    (Platform.environment['PUB_ENVIRONMENT'] ?? '').contains('flutter_cli');

/// A regular expression to match the script path of a pub script running from
/// source in the Dart repo.
final _dartRepoRegExp = RegExp(
  r'/third_party/pkg/pub/('
  r'bin/pub\.dart'
  r'|'
  r'test/.*_test\.dart'
  r')$',
);

/// Whether pub is running from source in the Dart repo.
///
/// This can happen when running tests against the repo, as well as when
/// building Observatory.
final bool runningFromDartRepo = Platform.script.path.contains(_dartRepoRegExp);

/// The path to the root of the Dart repo.
///
/// This throws a [StateError] if it's called when not running pub from source
/// in the Dart repo.
final String dartRepoRoot =
    (() {
      if (!runningFromDartRepo) {
        throw StateError('Not running from source in the Dart repo.');
      }

      // Get the URL of the repo root in a way that works when either both
      // running as a test or as a pub executable.
      final url = Platform.script.replace(
        path: Platform.script.path.replaceAll(_dartRepoRegExp, ''),
      );
      return p.fromUri(url);
    })();

/// Displays a message and reads a yes/no confirmation from the user.
///
/// Returns a [Future] that completes to `true` if the user confirms or `false`
/// if they do not.
///
/// This will automatically append " (y/N)?" to the message, so [message]
/// should just be a fragment like, "Are you sure you want to proceed". The
/// default for an empty response, or any response not starting with `y` or `Y`
/// is false.
Future<bool> confirm(String message) async {
  final reply = await stdinPrompt('$message (y/N)?');
  return RegExp(r'^[yY]').hasMatch(reply);
}

/// Writes [prompt] and reads a line from stdin.
Future<String> stdinPrompt(String prompt, {bool? echoMode}) async {
  if (runningFromTest) {
    log.message(prompt);
  } else {
    stdout.write('$prompt ');
  }
  if (echoMode != null && stdin.hasTerminal) {
    final previousEchoMode = stdin.echoMode;
    try {
      stdin.echoMode = echoMode;
      final result = stdin.readLineSync() ?? '';
      stdout.write('\n');
      return result;
    } finally {
      stdin.echoMode = previousEchoMode;
    }
  } else {
    return stdin.readLineSync() ?? '';
  }
}

/// Returns `true` if [stdout] should be treated as a terminal.
///
/// The detected behaviour can be overridden with the environment variable
/// [EnvironmentKeys.forceTerminalOutput].
bool get terminalOutputForStdout {
  final environmentValue =
      Platform.environment[EnvironmentKeys.forceTerminalOutput];
  if (environmentValue == null || environmentValue == '') {
    return stdout.hasTerminal;
  } else if (environmentValue == '0') {
    return false;
  } else if (environmentValue == '1') {
    return true;
  } else {
    throw DataException(
      'Environment variable ${EnvironmentKeys.forceTerminalOutput} has '
      'unsupported value: $environmentValue.',
    );
  }
}

/// Flushes the stdout and stderr streams, then exits the program with the given
/// status code.
///
/// This returns a Future that will never complete, since the program will have
/// exited already. This is useful to prevent Future chains from proceeding
/// after you've decided to exit.
Future flushThenExit(int status) {
  return Future.wait([
    stdout.close(),
    stderr.close(),
  ]).then((_) => exit(status));
}

/// Returns a [EventSink] that pipes all data to [consumer] and a [Future] that
/// will succeed when [EventSink] is closed or fail with any errors that occur
/// while writing.
(EventSink<T> consumerSink, Future done) _consumerToSink<T>(
  StreamConsumer<T> consumer,
) {
  final controller = StreamController<T>(sync: true);
  final done = controller.stream.pipe(consumer);
  return (controller.sink, done);
}

/// Spawns and runs the process located at [executable], passing in [args].
///
/// Returns a [Future] that will complete with the results of the process after
/// it has ended.
///
/// The spawned process will inherit its parent's environment variables. If
/// [environment] is provided, that will be used to augment (not replace) the
/// the inherited variables.
Future<StringProcessResult> runProcess(
  String executable,
  List<String> args, {
  String? workingDir,
  Map<String, String>? environment,
  bool runInShell = false,
  Encoding stdoutEncoding = systemEncoding,
  Encoding stderrEncoding = systemEncoding,
}) {
  ArgumentError.checkNotNull(executable, 'executable');

  return _descriptorPool.withResource(() async {
    ProcessResult result;
    try {
      (executable, args) = _sanitizeExecutablePath(
        executable,
        args,
        workingDir: workingDir,
      );
      result = await Process.run(
        executable,
        args,
        workingDirectory: workingDir,
        environment: environment,
        runInShell: runInShell,
        stdoutEncoding: stdoutEncoding,
        stderrEncoding: stderrEncoding,
      );
    } on IOException catch (e) {
      throw RunProcessException(
        'Pub failed to run subprocess `$executable`: $e',
      );
    }

    log.processResult(executable, result);
    return StringProcessResult(
      result.stdout as String,
      result.stderr as String,
      result.exitCode,
    );
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
@visibleForTesting
Future<PubProcess> startProcess(
  String executable,
  List<String> args, {
  String? workingDir,
  Map<String, String>? environment,
  bool runInShell = false,
}) {
  return _descriptorPool.request().then((resource) async {
    Process ioProcess;
    try {
      (executable, args) = _sanitizeExecutablePath(
        executable,
        args,
        workingDir: workingDir,
      );
      ioProcess = await Process.start(
        executable,
        args,
        workingDirectory: workingDir,
        environment: environment,
        runInShell: runInShell,
      );
    } on IOException catch (e) {
      throw RunProcessException(
        'Pub failed to run subprocess `$executable`: $e',
      );
    }

    final process = PubProcess(ioProcess);
    unawaited(process.exitCode.whenComplete(resource.release));
    return process;
  });
}

/// Like [runProcess], but synchronous.
StringProcessResult runProcessSync(
  String executable,
  List<String> args, {
  String? workingDir,
  Map<String, String>? environment,
  bool runInShell = false,
  Encoding stdoutEncoding = systemEncoding,
  Encoding stderrEncoding = systemEncoding,
}) {
  ArgumentError.checkNotNull(executable, 'executable');
  ProcessResult result;
  try {
    (executable, args) = _sanitizeExecutablePath(
      executable,
      args,
      workingDir: workingDir,
    );
    result = Process.runSync(
      executable,
      args,
      workingDirectory: workingDir,
      environment: environment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  } on IOException catch (e) {
    throw RunProcessException('Pub failed to run subprocess `$executable`: $e');
  }
  log.processResult(executable, result);
  return StringProcessResult(
    result.stdout as String,
    result.stderr as String,
    result.exitCode,
  );
}

/// Like [runProcess], but synchronous.
/// Always outputs stdout as `List<int>`.
BytesProcessResult runProcessSyncBytes(
  String executable,
  List<String> args, {
  String? workingDir,
  Map<String, String>? environment,
  bool runInShell = false,
  Encoding stderrEncoding = systemEncoding,
}) {
  ProcessResult result;
  try {
    (executable, args) = _sanitizeExecutablePath(
      executable,
      args,
      workingDir: workingDir,
    );
    result = Process.runSync(
      executable,
      args,
      workingDirectory: workingDir,
      environment: environment,
      runInShell: runInShell,
      stdoutEncoding: null,
      stderrEncoding: stderrEncoding,
    );
  } on IOException catch (e) {
    throw RunProcessException('Pub failed to run subprocess `$executable`: $e');
  }
  log.processResult(executable, result);
  return BytesProcessResult(
    result.stdout as List<int>,
    result.stderr as String,
    result.exitCode,
  );
}

/// Adaptation of ProcessResult when stdout is a `List<String>`.
class StringProcessResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  StringProcessResult(this.stdout, this.stderr, this.exitCode);
  bool get success => exitCode == exit_codes.SUCCESS;
}

/// Adaptation of ProcessResult when stdout is a `List<bytes>`.
class BytesProcessResult {
  final Uint8List stdout;
  final String stderr;
  final int exitCode;
  BytesProcessResult(List<int> stdout, this.stderr, this.exitCode)
    : // Not clear that we need to do this, but seems harmless.
      stdout = stdout is Uint8List ? stdout : Uint8List.fromList(stdout);
  bool get success => exitCode == exit_codes.SUCCESS;
}

/// A wrapper around [Process] that exposes `dart:async`-style APIs.
class PubProcess {
  /// The underlying `dart:io` [Process].
  final Process _process;

  /// The sink used for passing data to the process's standard input stream.
  ///
  /// Errors on this stream are surfaced through [stdinClosed], [stdout],
  /// [stderr], and [exitCode], which are all members of an [ErrorGroup].
  final EventSink<List<int>> stdin;

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
  final Future stdinClosed;

  /// The process's standard output stream.
  ///
  /// This is in an [ErrorGroup] with [stdinClosed], [stderr], and [exitCode],
  /// so any error in process will be passed to it, but won't reach the
  /// top-level error handler unless nothing has handled it.
  final ByteStream stdout;

  /// The process's standard error stream.
  ///
  /// This is in an [ErrorGroup] with [stdinClosed], [stdout], and [exitCode],
  /// so any error in process will be passed to it, but won't reach the
  /// top-level error handler unless nothing has handled it.
  final ByteStream stderr;

  /// A [Future] that will complete to the process's exit code once the process
  /// has finished running.
  ///
  /// This is in an [ErrorGroup] with [stdinClosed], [stdout], and [stderr], so
  /// any error in process will be passed to it, but won't reach the top-level
  /// error handler unless nothing has handled it.
  final Future<int> exitCode;

  PubProcess._(
    this._process, {
    required this.stdin,
    required this.stdinClosed,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  /// Creates a new [PubProcess] wrapping [process].
  factory PubProcess(Process process) {
    final errorGroup = ErrorGroup();

    final (consumerSink, done) = _consumerToSink(process.stdin);
    final stdinClosed = errorGroup.registerFuture(done);

    final stdout = ByteStream(errorGroup.registerStream(process.stdout));
    final stderr = ByteStream(errorGroup.registerStream(process.stderr));

    final exitCodeCompleter = Completer<int>();
    final exitCode = errorGroup.registerFuture(exitCodeCompleter.future);
    process.exitCode.then(exitCodeCompleter.complete);

    return PubProcess._(
      process,
      stdin: consumerSink,
      stdinClosed: stdinClosed,
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
    );
  }

  /// Sends [signal] to the underlying process.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}

/// Sanitizes the executable path on windows for [Process.start], [Process.run]
/// and [Process.runSync].
(String, List<String>) _sanitizeExecutablePath(
  String executable,
  List<String> args, {
  String? workingDir,
}) {
  // TODO(rnystrom): Should dart:io just handle this?
  // Spawning a process on Windows will not look for the executable in the
  // system path. So, if executable looks like it needs that (i.e. it doesn't
  // have any path separators in it), then spawn it through a shell.
  if (Platform.isWindows && !executable.contains('\\')) {
    args = ['/c', executable, ...args];
    executable = 'cmd';
  }

  log.process(executable, args, workingDir ?? '.');
  return (executable, args);
}

/// Updates [path]'s modification time.
void touch(String path) {
  log.fine('Touching `$path`');
  File(path).setLastModifiedSync(DateTime.now());
}

/// Creates a temporary directory and passes its path to [fn].
///
/// Once the [Future] returned by [fn] completes, the temporary directory and
/// all its contents are deleted. [fn] can also return `null`, in which case
/// the temporary directory is deleted immediately afterwards.
///
/// Returns a future that completes to the value that the future returned from
/// [fn] completes to.
Future<T> withTempDir<T>(FutureOr<T> Function(String path) fn) async {
  final tempDir = await _createSystemTempDir();
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
  final server =
      host == 'localhost'
          ? await HttpMultiServer.loopback(port)
          : await HttpServer.bind(host, port);
  server.autoCompress = true;
  return server;
}

/// Extracts a single file from a `.tar.gz` [stream].
///
/// [filename] should be the relative path inside the archive (with unix
/// separators '/').
///
/// Throws a `FormatException` if that file did not exist.
Future<Uint8List> extractFileFromTarGz(
  Stream<List<int>> stream,
  String filename,
) async {
  final reader = TarReader(stream.transform(gzip.decoder));
  filename = p.posix.normalize(filename);
  while (await reader.moveNext()) {
    final entry = reader.current;
    if (p.posix.normalize(entry.name) != filename) continue;
    if (!(entry.type == TypeFlag.reg || entry.type == TypeFlag.regA)) {
      // Can only read regular files.
      throw FormatException('$filename is not a file');
    }
    return await collectBytes(entry.contents);
  }
  throw FormatException('Could not find $filename in archive');
}

/// Extracts a `.tar.gz` file from [stream] to [destination].
Future<void> extractTarGz(Stream<List<int>> stream, String destination) async {
  log.fine('Extracting .tar.gz stream to $destination.');

  destination = p.absolute(destination);
  final reader = TarReader(stream.transform(gzip.decoder));
  final paths = <String>{};
  while (await reader.moveNext()) {
    final entry = reader.current;

    final filePath = p.joinAll([
      destination,
      // Tar file names always use forward slashes
      ...p.posix.split(entry.name),
    ]);
    if (!paths.add(filePath)) {
      // The tar file contained the same entry twice. Assume it is broken.
      await reader.cancel();
      throw FormatException('Tar file contained duplicate path ${entry.name}');
    }

    if (!(p.isWithin(destination, filePath) ||
        // allow including '.' as an entry in the tar.gz archive.
        (entry.type == TypeFlag.dir && p.equals(destination, filePath)))) {
      // The tar contains entries that would be written outside of the
      // destination. That doesn't happen by accident, assume that the tar file
      // is malicious.
      await reader.cancel();
      throw FormatException('Invalid tar entry: `${entry.name}`');
    }

    final parentDirectory = p.dirname(filePath);

    bool checkValidTarget(String linkTarget) {
      final isValid = p.isWithin(destination, linkTarget);
      if (!isValid) {
        log.fine('Skipping ${entry.name}: Invalid link target');
      }

      return isValid;
    }

    switch (entry.type) {
      case TypeFlag.dir:
        ensureDir(filePath);
        break;
      case TypeFlag.reg:
      case TypeFlag.regA:
        // Regular file
        deleteIfLink(filePath);
        ensureDir(parentDirectory);
        await createFileFromStream(entry.contents, filePath);

        if (Platform.isLinux || Platform.isMacOS) {
          // Apply executable bits from tar header, but don't change r/w bits
          // from the default
          final mode = _defaultMode | (entry.header.mode & _executableMask);

          if (mode != _defaultMode) {
            _chmod(mode, filePath);
          }
        }
        break;
      case TypeFlag.symlink:
        // Link to another file in this tar, relative from this entry.
        final resolvedTarget = p.joinAll([
          parentDirectory,
          ...p.posix.split(entry.header.linkName!),
        ]);
        if (!checkValidTarget(resolvedTarget)) {
          // Don't allow links to files outside of this tar.
          break;
        }

        ensureDir(parentDirectory);
        createSymlink(
          p.relative(resolvedTarget, from: parentDirectory),
          filePath,
        );
        break;
      case TypeFlag.link:
        // We generate hardlinks as symlinks too, but their linkName is relative
        // to the root of the tar file (unlike symlink entries, whose linkName
        // is relative to the entry itself).
        final fromDestination = p.join(destination, entry.header.linkName);
        if (!checkValidTarget(fromDestination)) {
          break; // Link points outside of the tar file.
        }

        final fromFile = p.relative(fromDestination, from: parentDirectory);
        ensureDir(parentDirectory);
        createSymlink(fromFile, filePath);
        break;
      default:
        // Only extract files
        continue;
    }
  }

  log.fine('Extracted .tar.gz to $destination.');
}

/// Create a .tar.gz archive from a list of entries.
///
/// Each entry is the path to a directory or file. The root of the archive is
/// considered to be [baseDir], which defaults to the current working directory.
///
/// Returns a [ByteStream] that emits the contents of the archive.
ByteStream createTarGz(List<String> contents, {required String baseDir}) {
  final buffer = StringBuffer();
  buffer.write('Creating .tar.gz stream containing:\n');
  contents.forEach(buffer.writeln);
  log.fine(buffer.toString());

  ArgumentError.checkNotNull(baseDir, 'baseDir');
  baseDir = p.normalize(p.absolute(baseDir));

  final tarContents = Stream.fromIterable(
    contents.map((entry) {
      entry = p.normalize(p.absolute(entry));
      if (p.equals(baseDir, entry)) {
        return null;
      }
      if (!p.isWithin(baseDir, entry)) {
        throw ArgumentError('Entry $entry is not inside $baseDir.');
      }

      final relative = p.relative(entry, from: baseDir);
      // On Windows, we can't open some files without normalizing them
      final file = File(p.normalize(entry));
      final stat = file.statSync();

      // Ensure paths in tar files use forward slashes
      final name = p.url.joinAll(p.split(relative));

      if (stat.type == FileSystemEntityType.link) {
        log.message(
          '$entry is a link locally, but will be uploaded as a '
          'duplicate file.',
        );
      }
      if (stat.type == FileSystemEntityType.directory) {
        return TarEntry(
          TarHeader(
            name: name,
            mode: _defaultMode | _executableMask,
            typeFlag: TypeFlag.dir,
            userName: 'pub',
            groupName: 'pub',
          ),
          Stream.fromIterable([]),
        );
      } else {
        return TarEntry(
          TarHeader(
            name: name,
            // We want to keep executable bits, but otherwise use the default
            // file mode
            mode: _defaultMode | (stat.mode & _executableMask),
            size: stat.size,
            modified: stat.changed,
            userName: 'pub',
            groupName: 'pub',
          ),
          file.openRead(),
        );
      }
    }).nonNulls,
  );

  return ByteStream(
    tarContents
        .transform(tarWriterWith(format: OutputFormat.gnuLongName))
        .transform(gzip.encoder),
  );
}

/// The location for dart-specific configuration.
///
/// `null` if no config dir could be found.
final String? dartConfigDir = () {
  if (runningFromTest &&
      Platform.environment.containsKey('_PUB_TEST_CONFIG_DIR')) {
    return p.join(Platform.environment['_PUB_TEST_CONFIG_DIR']!, 'dart');
  }
  try {
    return applicationConfigHome('dart');
  } on EnvironmentNotFoundException {
    return null;
  }
}();

/// Escape [x] for users to copy-paste in bash.
///
/// If x is alphanumeric we leave it as is.
///
/// Otherwise, wrap with single quotation, and use '\'' to insert single quote.
String escapeShellArgument(String x) =>
    RegExp(r'^[a-zA-Z0-9-_=@.^]+$').stringMatch(x) == null
        ? "'${x.replaceAll(r'\', r'\\').replaceAll("'", r"'\''")}'"
        : x;

/// Returns all parent directories of [path], starting from [path] to the
/// filesystem root.
///
/// If [path] is relative the directories will also be.
///
/// If [from] is passed, directories are made relative to that.
///
/// Examples:
///   parentDirs('/a/b/c') => ('/a/b/c', '/a/b', '/a', '/')
///   parentDirs('./d/e', from: '/a/b/c') => ('./d/e', './d', '.', '..', '../..', '../../..')
Iterable<String> parentDirs(String path, {String? from}) sync* {
  var relative = false;
  var d = path;
  while (true) {
    if (relative) {
      yield p.relative(d, from: from);
    } else {
      yield d;
    }
    if (!p.isWithin(from ?? p.current, d)) {
      d = p.normalize(p.join(from ?? p.current, d));
      relative = true;
    }
    final parent = p.dirname(d);
    if (parent == d) break;
    d = parent;
  }
}
