// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A trivial embedding of the pub command. Used from tests.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:pub/pub.dart';
import 'package:pub/src/command.dart';
import 'package:pub/src/exit_codes.dart' as exit_codes;
import 'package:pub/src/log.dart' as log;
import 'package:usage/usage.dart';

final Analytics loggingAnalytics = _LoggingAnalytics();

// A command for explicitly throwing an exception, to test the handling of
// unexpected eceptions.
class ThrowingCommand extends PubCommand {
  @override
  String get name => 'fail';

  @override
  String get description => 'Throws an exception';

  bool get hide => true;

  @override
  Future<int> runProtected() async {
    throw StateError('Pub has crashed');
  }
}

// A command for testing the ensurePubspecResolved functionality
class EnsurePubspecResolvedCommand extends PubCommand {
  @override
  String get name => 'ensure-pubspec-resolved';

  @override
  String get description => 'Resolves pubspec.yaml if needed';

  @override
  bool get hidden => true;

  @override
  Future<int> runProtected() async {
    await ensurePubspecResolved('.');
    return 0;
  }
}

class RunCommand extends Command<int> {
  @override
  String get name => 'run';

  @override
  String get description => 'runs a dart app';

  @override
  Future<int> run() async {
    final executable = await getExecutableForCommand(argResults!.rest.first);
    final packageConfig = executable.packageConfig;
    final process = await Process.start(
      Platform.executable,
      [
        if (packageConfig != null) '--packages=$packageConfig',
        executable.executable,
        ...argResults!.rest.skip(1)
      ],
      mode: ProcessStartMode.inheritStdio,
    );

    return await process.exitCode;
  }
}

class Runner extends CommandRunner<int> {
  late ArgResults _options;

  Runner() : super('pub_command_runner', 'Tests the embeddable pub command.') {
    final analytics = Platform.environment['_PUB_LOG_ANALYTICS'] == 'true'
        ? PubAnalytics(
            () => loggingAnalytics,
            dependencyKindCustomDimensionName: 'cd1',
          )
        : null;
    addCommand(
      pubCommand(analytics: analytics, isVerbose: () => _options['verbose'])
        ..addSubcommand(ThrowingCommand())
        ..addSubcommand(EnsurePubspecResolvedCommand()),
    );
    addCommand(RunCommand());
    argParser.addFlag('verbose');
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      _options = super.parse(args);
      if (_options['verbose']) {
        log.verbosity = log.Verbosity.all;
      }
      return await runCommand(_options);
    } on UsageException catch (error) {
      log.exception(error);
      return exit_codes.USAGE;
    }
  }

  @override
  Future<int> runCommand(ArgResults topLevelResults) async {
    return await super.runCommand(topLevelResults) ?? 0;
  }
}

Future<void> main(List<String> arguments) async {
  exitCode = await Runner().run(arguments);
}

class _LoggingAnalytics extends AnalyticsMock {
  _LoggingAnalytics() {
    onSend.listen((event) {
      stderr.writeln('[analytics]${json.encode(event)}');
    });
  }

  @override
  bool get firstRun => false;

  @override
  Future sendScreenView(String viewName, {Map<String, String>? parameters}) {
    parameters ??= <String, String>{};
    parameters['viewName'] = viewName;
    return _log('screenView', parameters);
  }

  @override
  Future sendEvent(
    String category,
    String action, {
    String? label,
    int? value,
    Map<String, String>? parameters,
  }) {
    parameters ??= <String, String>{};
    return _log(
      'event',
      {'category': category, 'action': action, 'label': label, 'value': value}
        ..addAll(parameters),
    );
  }

  @override
  Future sendSocial(String network, String action, String target) =>
      _log('social', {'network': network, 'action': action, 'target': target});

  @override
  Future sendTiming(
    String variableName,
    int time, {
    String? category,
    String? label,
  }) {
    return _log('timing', {
      'variableName': variableName,
      'time': time,
      'category': category,
      'label': label
    });
  }

  Future<void> _log(String hitType, Map message) async {
    final encoded = json.encode({'hitType': hitType, 'message': message});
    stderr.writeln('[analytics]: $encoded');
  }
}
