import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:pub/src/pub_embeddable_command.dart';
import 'package:pub/src/log.dart' as log;
import 'package:pub/src/io.dart';
import 'package:pub/src/exit_codes.dart' as exit_codes;

class Runner extends CommandRunner {
  ArgResults _options;

  Runner() : super('pub_command_runner', 'Tests the embeddable pub command.') {
    addCommand(PubEmbeddableCommand());
  }

  @override
  Future run(Iterable<String> args) async {
    try {
      _options = super.parse(args);

      await runCommand(_options);
    } on UsageException catch (error) {
      log.exception(error);
      await flushThenExit(exit_codes.USAGE);
    }
  }

  @override
  Future runCommand(ArgResults topLevelResults) async {
    await super.runCommand(topLevelResults);
  }
}

Future<void> main(List<String> arguments) async {
  await Runner().run(arguments);
}
