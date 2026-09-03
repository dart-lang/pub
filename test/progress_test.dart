// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pub/src/log.dart' as log;
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

  final bool _hasTerminal;

  _MockStdout({bool hasTerminal = true}) : _hasTerminal = hasTerminal;

  @override
  bool get hasTerminal => _hasTerminal;

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
  setUp(resetGracePeriod);

  tearDown(resetGracePeriod);

  test('stopAndClear erases line with ANSI escape sequence', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.always;
      try {
        final progress = Progress('Resolving dependencies');
        expect(mockStdout.buffer.toString(), 'Resolving dependencies... ');
        progress.stopAndClear();
        expect(
          mockStdout.buffer.toString(),
          'Resolving dependencies... \r${log.eraseLine}',
        );
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test('transient progress produces no output when ANSI is disabled', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.never;
      try {
        final progress = Progress('Resolving dependencies', transient: true);
        expect(mockStdout.buffer.toString(), isEmpty);
        progress.stopAndClear();
        expect(mockStdout.buffer.toString(), isEmpty);
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test(
    'non-transient progress logs once without animation when ANSI is disabled',
    () async {
      final mockStdout = _MockStdout();
      await IOOverrides.runZoned(() async {
        forceColors = ForceColorOption.never;
        try {
          final progress = Progress('Resolving dependencies');
          expect(mockStdout.buffer.toString(), 'Resolving dependencies...\n');
          progress.stop();
          expect(mockStdout.buffer.toString(), 'Resolving dependencies...\n');
        } finally {
          forceColors = ForceColorOption.auto;
        }
      }, stdout: () => mockStdout);
    },
  );

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
      progress.stopAndClear();
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
        progress.stopAndClear();
        expect(
          mockStdout.buffer.toString(),
          'Resolving dependencies... \r${log.eraseLine}',
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
          currentProgressGracePeriod.markProgressShown();
          final progress = Progress('Downloading packages');
          expect(mockStdout.buffer.toString(), 'Downloading packages... ');
          progress.stopAndClear();
        } finally {
          forceColors = ForceColorOption.auto;
          resetGracePeriod();
        }
      }, stdout: () => mockStdout);
    },
  );

  test('withProgressGracePeriod shares progress state across zone', () async {
    final mockStdout = _MockStdout();
    final customGrace = ProgressGracePeriod();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.always;
      try {
        await withProgressGracePeriod(() async {
          expect(currentProgressGracePeriod, same(customGrace));
          expect(currentProgressGracePeriod.hasShownProgress, isFalse);
          final progress = Progress('Resolving');
          expect(currentProgressGracePeriod.hasShownProgress, isTrue);
          expect(customGrace.hasShownProgress, isTrue);
          progress.stopAndClear();
        }, progressGracePeriod: customGrace);
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test('progress cleans up and stops timer on synchronous exception', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.always;
      try {
        expect(
          () => log.progress<void>(
            'Failing task',
            () => throw StateError('boom'),
          ),
          throwsA(isA<StateError>()),
        );
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test('stopAnimating erases elapsed time before newline', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.always;
      try {
        final progress = Progress('Animating task', delay: Duration.zero);
        // Wait long enough for timer to tick and print time indicator
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        progress.stopAnimating();
        final output = mockStdout.buffer.toString();
        expect(output, contains('\rAnimating task... ${log.eraseToLineEnd}\n'));
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test('stopAnimating erases entire line when transient', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.always;
      try {
        final progress = Progress(
          'Transient task',
          delay: Duration.zero,
          transient: true,
        );
        progress.stopAnimating();
        final output = mockStdout.buffer.toString();
        expect(output, 'Transient task... \r${log.eraseLine}');
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test('stopAnimating is a no-op when ANSI is disabled', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      forceColors = ForceColorOption.never;
      try {
        final progress = Progress('Animating task', delay: Duration.zero);
        expect(mockStdout.buffer.toString(), 'Animating task...\n');
        progress.stopAnimating();
        expect(mockStdout.buffer.toString(), 'Animating task...\n');
      } finally {
        forceColors = ForceColorOption.auto;
      }
    }, stdout: () => mockStdout);
  });

  test('ProgressGracePeriod rejects negative defaultGracePeriod', () {
    expect(
      () => ProgressGracePeriod(
        defaultGracePeriod: const Duration(milliseconds: -1),
      ),
      throwsArgumentError,
    );
  });

  test('log.progress supports synchronous callbacks', () async {
    final mockStdout = _MockStdout();
    await IOOverrides.runZoned(() async {
      final result = await log.progress('Sync task', () => 42);
      expect(result, 42);
    }, stdout: () => mockStdout);
  });

  test('ProgressGracePeriod starts an unstarted stopwatch', () async {
    final stopwatch = Stopwatch();
    expect(stopwatch.isRunning, isFalse);
    final grace = ProgressGracePeriod(stopwatch: stopwatch);
    expect(stopwatch.isRunning, isTrue);
    expect(
      grace.remainingDelay,
      lessThanOrEqualTo(const Duration(milliseconds: 500)),
    );
  });

  test(
    'transient progress produces no output when stdout has no terminal',
    () async {
      final mockStdout = _MockStdout(hasTerminal: false);
      await IOOverrides.runZoned(() async {
        final result = await log.progress(
          'Transient task',
          () async => 42,
          transient: true,
        );
        expect(result, 42);
        expect(mockStdout.buffer.toString(), isEmpty);
      }, stdout: () => mockStdout);
    },
  );
}
