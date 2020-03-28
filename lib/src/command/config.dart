// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../command.dart';
<<<<<<< HEAD
import '../config_helper.dart';
import '../log.dart' as log;
=======
import '../log.dart' as log;
import '../config_helper.dart';
>>>>>>> Add new command pub config

/// Handles the `config` pub command.
class ConfigCommand extends PubCommand {
  @override
  String get name => 'config';

  @override
  String get description => 'Change configuration for pub.';

  @override
  String get invocation => 'pub config [options]';

  ConfigCommand() {
    argParser.addOption('verbosity',
        abbr: 'v',
        help: 'Default verbosity level',
        allowed: ['none', 'error', 'warning', 'normal', 'io', 'solver', 'all']);

    argParser.addFlag(
      'show',
      abbr: 's',
      help: 'Show current config',
<<<<<<< HEAD
=======
      defaultsTo: false,
>>>>>>> Add new command pub config
      negatable: false,
    );

    argParser.addFlag('is-verbose',
<<<<<<< HEAD
        help: 'Print a message if output is verbose', negatable: false);

    argParser.addFlag('make-invalid', negatable: false, hide: true);

    argParser.addFlag('make-empty', negatable: false, hide: true);
=======
    help: 'Print a message if output is verbose',
    negatable: false,
    defaultsTo: false);
>>>>>>> Add new command pub config
  }

  @override
  void run() {
<<<<<<< HEAD
    const availableSettings = ['verbosity'];
    const standardConfig = '''verbosity: "normal"''';
    var conf = ConfigHelper(availableSettings, standardConfig);
    if (argResults.wasParsed('make-invalid')) {
      conf.makeInvalid();
    } else if (argResults.wasParsed('make-empty')) {
      conf.createEmptyConfigFile();
    }
=======
    List<String> availableSettings = ['verbosity'];
    String standardConfig = '''verbosity: "normal"''';
    var conf = new ConfigHelper(availableSettings, standardConfig);
>>>>>>> Add new command pub config
    var _buffer = StringBuffer();
    var maxRestArguments = 0;

    /// show flag can have infinitely many arguments (they are validated below)
<<<<<<< HEAD
    if (argResults.wasParsed('show')) {
      maxRestArguments = availableSettings.length;
    }

    if (argResults.rest.length > maxRestArguments) {
      usageException('Too many arguments');
    }
=======
    if (argResults.wasParsed('show'))
      maxRestArguments = availableSettings.length;

    if (argResults.rest.length > maxRestArguments)
      usageException('Too many arguments');
>>>>>>> Add new command pub config

    if (argResults.wasParsed('verbosity')) {
      conf.set('verbosity', argResults['verbosity']);
      conf.write();
      _buffer.writeln('verbosity set to ${argResults['verbosity']}');
      printBuffer(_buffer);
      return;
    }

    if (argResults.wasParsed('show')) {
<<<<<<< HEAD
      final listToBeLooped =
          argResults.rest.isNotEmpty ? argResults.rest : availableSettings;
      if (listToBeLooped == availableSettings) {
        _buffer.writeln('Current config:');
      }

      for (var i = 0; i < listToBeLooped.length; i++) {
        if (availableSettings.contains(listToBeLooped[i])) {
          _buffer.writeln(
              listToBeLooped[i] + ': ' + conf.get(listToBeLooped[i]) ??
                  'not set');
        } else {
          usageException('No such config option: ${listToBeLooped[i]}');
=======
      List<String> listToBeLooped =
          (argResults.rest.length > 0 ? argResults.rest : availableSettings);
      if (listToBeLooped == availableSettings)
        _buffer.writeln('Current config:');

      for (int i = 0; i < listToBeLooped.length; i++) {
        if (availableSettings.contains(listToBeLooped[i])) {
          _buffer.writeln(
              listToBeLooped[i] + ": " + conf.get(listToBeLooped[i]) ??
                  'not set');
        } else {
          usageException("No such config option: ${listToBeLooped[i]}");
>>>>>>> Add new command pub config
        }
      }
      printBuffer(_buffer);
      return;
    }

<<<<<<< HEAD
    if (argResults.wasParsed('is-verbose')) {
      if (log.verbosity == log.Verbosity.ALL) {
        _buffer.writeln('pub currently has verbose output');
      }
=======
    if(argResults.wasParsed('is-verbose')){
      if(log.verbosity == log.Verbosity.ALL) _buffer.writeln('pub currently has verbose output');
>>>>>>> Add new command pub config
      printBuffer(_buffer);
      return;
    }

<<<<<<< HEAD
    printUsage();
=======
    this.printUsage();
>>>>>>> Add new command pub config
  }

  /// This function prints a String Buffer regardless of the verbosity setting
  void printBuffer(StringBuffer _buf) {
    var currentVerbosity = log.verbosity;
    log.verbosity = log.Verbosity.ALL;
    log.message(_buf);
    log.verbosity = currentVerbosity;
  }
}
