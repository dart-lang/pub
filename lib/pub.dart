import 'package:args/command_runner.dart';
import 'src/pub_embeddable_command.dart';
export 'src/executable.dart' show getExecutableForCommand;

/// Returns a [Command] for pub functionality that can be used by an embedding
/// CommandRunner.
Command pubCommand() => PubEmbeddableCommand();
