// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub/src/ascii_tree.dart' as ascii_tree;
import 'package:pub/src/io.dart';
import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:test/test.dart';

import 'descriptor.dart' as d;
import 'test_pub.dart';

final _isCI = () {
  final p = RegExp(r'^1|(?:true)$', caseSensitive: false);
  final ci = Platform.environment['CI'];
  return ci != null && ci.isNotEmpty && p.hasMatch(ci);
}();

/// Find the current `_test.dart` filename invoked from stack-trace.
String _findCurrentTestFilename() =>
    Trace.current().frames
        .lastWhere(
          (frame) =>
              frame.uri.isScheme('file') &&
              p.basename(frame.uri.toFilePath()).endsWith('_test.dart'),
        )
        .uri
        .toFilePath();

class GoldenTestContext {
  static const _endOfSection =
      ''
      '--------------------------------'
      ' END OF OUTPUT '
      '---------------------------------\n\n';

  final File _goldenFile;
  final String _header;
  final _results = <String>[];
  late bool _shouldRegenerateGolden;
  final bool colors;
  bool _generatedNewData = false; // track if new data is generated
  int _nextSectionIndex = 0;

  GoldenTestContext._(
    String currentTestFile,
    String testName, {
    required this.colors,
  }) : _goldenFile = File(
         p.join(
           'test',
           'testdata',
           'goldens',
           p.relative(
             currentTestFile.replaceAll(RegExp(r'\.dart$'), ''),
             from: p.join(p.current, 'test'),
           ),
           // Sanitize the name, and add .ans or .txt.
           '${testName.replaceAll(RegExp(r'[<>:"/\|?*%#]'), '~')}.'
               '${colors ? 'ans' : 'txt'}',
         ),
       ),
       _header = '# GENERATED BY: ${p.relative(currentTestFile)}\n\n';

  String get _goldenFilePath => _goldenFile.path;

  void _readGoldenFile() {
    if (RegExp(
          r'^1|(?:true)$',
          caseSensitive: false,
        ).hasMatch(Platform.environment['_PUB_TEST_WRITE_GOLDEN'] ?? '') ||
        !_goldenFile.existsSync()) {
      _shouldRegenerateGolden = true;
    } else {
      _shouldRegenerateGolden = false;
      // Read the golden file for this test
      var text = _goldenFile.readAsStringSync().replaceAll('\r\n', '\n');
      // Strip header line
      if (text.startsWith('#') && text.contains('\n\n')) {
        text = text.substring(text.indexOf('\n\n') + 2);
      }
      _results.addAll(text.split(_endOfSection));
    }
  }

  /// Expect section [sectionIndex] to match [actual].
  void _expectSection(int sectionIndex, String actual) {
    if (!_shouldRegenerateGolden &&
        _results.length > sectionIndex &&
        _results[sectionIndex].isNotEmpty) {
      expect(
        actual,
        equals(_results[sectionIndex]),
        reason: 'Expect matching section $sectionIndex from "$_goldenFilePath"',
      );
    } else {
      while (_results.length <= sectionIndex) {
        _results.add('');
      }
      _results[sectionIndex] = actual;
      _generatedNewData = true;
    }
  }

  void _writeGoldenFile() {
    // If we generated new data, then we need to write a new file, and fail the
    // test case, or mark it as skipped.
    if (_generatedNewData) {
      // This enables writing the updated file when run in otherwise hermetic
      // settings.
      //
      // This is to make updating the golden files easier in a bazel environment
      // See https://docs.bazel.build/versions/2.0.0/user-manual.html#run .
      var goldenFile = _goldenFile;
      final workspaceDirectory =
          Platform.environment['BUILD_WORKSPACE_DIRECTORY'];
      if (workspaceDirectory != null) {
        goldenFile = File(p.join(workspaceDirectory, _goldenFilePath));
      }
      goldenFile
        ..createSync(recursive: true)
        ..writeAsStringSync(_header + _results.join(_endOfSection));

      // If running in CI we should fail if the golden file doesn't already
      // exist, or is missing entries.
      // This typically happens if we forgot to commit a file to git.
      if (_isCI) {
        fail(
          'Missing golden file: "$_goldenFilePath", '
          'try running tests again and commit the file',
        );
      } else {
        // If not running in CI, then we consider the test as skipped, we've
        // generated the file, but the user should run the tests again.
        // Or push to CI in which case we'll run the tests again anyways.
        markTestSkipped(
          'Generated golden file: "$_goldenFilePath" instead of running test',
        );
      }
    }
  }

  /// Expect the next section in the golden file to match [actual].
  ///
  /// This will create the section if it is missing.
  ///
  /// **Warning**: Take care when using this in an async context, sections are
  /// numbered based on the other in which calls are made. Hence, ensure
  /// consistent ordering of calls.
  void expectNextSection(String actual) =>
      _expectSection(_nextSectionIndex++, actual);

  /// Run `pub` [args] with [environment] variables in [workingDirectory], and
  /// log stdout/stderr and exit code to golden file.
  Future<void> run(
    List<String> args, {
    Map<String, String?>? environment,
    String? workingDirectory,
    String? stdin,
  }) async {
    // Create new section index number (before doing anything async)
    final sectionIndex = _nextSectionIndex++;
    final s = StringBuffer();
    s.writeln('## Section $sectionIndex');
    await runPubIntoBuffer(
      args,
      s,
      environment: environment,
      workingDirectory: workingDirectory,
      stdin: stdin,
    );

    _expectSection(sectionIndex, s.toString());
  }

  /// Removes ansi color codes from [s].
  String _stripColors(String s) {
    return s.replaceAll(RegExp('\u001b\\[.*?m'), '');
  }

  /// Log directory tree structure under [directory] to golden file.
  Future<void> tree([String? directory]) async {
    // Create new section index number (before doing anything async)
    final sectionIndex = _nextSectionIndex++;

    final target = p.join(d.sandbox, directory ?? '.');

    final s = StringBuffer();
    s.writeln('## Section $sectionIndex');
    if (directory != null) {
      s.writeln('\$ cd $directory');
    }
    s.writeln('\$ tree');
    final tree = ascii_tree.fromFiles(
      listDir(target, recursive: true),
      baseDir: target,
      showFileSizes: false,
    );
    s.writeln(colors ? tree : _stripColors(tree));

    _expectSection(sectionIndex, s.toString());
  }
}

/// Create a [test] with [GoldenTestContext] which allows running golden tests.
///
/// This will create a golden file containing output of calls to:
///  * [GoldenTestContext.run]
///  * [GoldenTestContext.tree]
///
/// The golden file with the recorded output will be created at:
///   `test/testdata/goldens/path/to/myfile_test/<name>.txt`
/// , when `path/to/myfile_test.dart` is the `_test.dart` file from which this
/// function is called.
///
/// If [colors] is `true` the file will be created with an `.ans` extension that
/// indicates ANSI colors will be used.
///
/// Such a file can eg. be viewed in vscode with this plugin:
/// https://marketplace.visualstudio.com/items?itemName=iliazeus.vscode-ansi
void testWithGolden(
  String name,
  FutureOr<void> Function(GoldenTestContext ctx) fn, {
  bool colors = false,
}) {
  final ctx = GoldenTestContext._(
    _findCurrentTestFilename(),
    name,
    colors: colors,
  );
  test(name, () async {
    ctx._readGoldenFile();
    await fn(ctx);
    ctx._writeGoldenFile();
  });
}
