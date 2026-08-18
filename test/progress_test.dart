// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pub/src/progress.dart';
import 'package:pub/src/utils.dart';
import 'package:test/test.dart';

final class _MockStdout implements Stdout {
  final StringBuffer buffer = StringBuffer();

  @override
  void write(Object? object) {
    buffer.write(object);
  }

  @override
  void writeln([Object? object = '']) {
    buffer.writeln(object);
  }

  @override
  void writeAll(Iterable objects, [String sep = '']) {
    buffer.writeAll(objects, sep);
  }

  @override
  void writeCharCode(int charCode) {
    buffer.writeCharCode(charCode);
  }

  @override
  void add(List<int> data) {
    buffer.write(utf8.decode(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      buffer.write(utf8.decode(chunk));
    }
  }

  @override
  Future close() async {}

  @override
  Future get done => Future.value();

  @override
  Future flush() async {}

  @override
  Encoding encoding = utf8;

  @override
  bool get hasTerminal => true;

  @override
  IOSink get nonBlocking => this;

  @override
  bool get supportsAnsiEscapes => true;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 25;

  @override
  String get lineTerminator => '\n';

  @override
  set lineTerminator(String value) {}
}

void main() {
  test('stopAndClear erases line with ANSI escape sequence', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.always;
      try {
        final progress = Progress('Resolving dependencies');
        expect(mockStdout.buffer.toString(), 'Resolving dependencies... ');
        await progress.stopAndClear();
        expect(
          mockStdout.buffer.toString(),
          'Resolving dependencies... \r\x1b[2K',
        );
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test('stopAndClear overwrites with spaces when ANSI is disabled', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.never;
      try {
        final progress = Progress('Resolving dependencies');
        expect(mockStdout.buffer.toString(), 'Resolving dependencies... ');
        await progress.stopAndClear();
        expect(
          mockStdout.buffer.toString(),
          'Resolving dependencies... \r${' ' * 26}\r',
        );
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test('stop prints completed newline', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      final progress = Progress('Resolving dependencies');
      expect(mockStdout.buffer.toString(), 'Resolving dependencies... ');
      progress.stop();
      expect(mockStdout.buffer.toString(), 'Resolving dependencies... \n');
    }, stdout: () => mockStdout);
  });

  test('delayed progress writes nothing if stopped before delay', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      final progress = Progress(
        'Resolving dependencies',
        delay: const Duration(milliseconds: 200),
      );
      expect(mockStdout.buffer.toString(), isEmpty);
      await progress.stopAndClear();
      expect(mockStdout.buffer.toString(), isEmpty);
    }, stdout: () => mockStdout);
  });

  test('delayed progress writes and clears if stopped after delay', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.always;
      try {
        final progress = Progress(
          'Resolving dependencies',
          delay: const Duration(milliseconds: 50),
        );
        expect(mockStdout.buffer.toString(), isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(mockStdout.buffer.toString(), 'Resolving dependencies... ');
        await progress.stopAndClear();
        expect(
          mockStdout.buffer.toString(),
          'Resolving dependencies... \r\x1b[2K',
        );
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test(
    'subsequent spinner starts immediately once progress was shown',
    () async {
      final mockStdout = _MockStdout();
      await IOOverrides.runZoned(() async {
        forceColors = ForceColorOption.always;
        try {
          hasShownProgress = true;
          final progress = Progress('Downloading packages');
          expect(mockStdout.buffer.toString(), 'Downloading packages... ');
          await progress.stopAndClear();
        } finally {
          forceColors = ForceColorOption.auto;
          resetGracePeriod();
        }
      }, stdout: () => mockStdout);
    },
  );
}
