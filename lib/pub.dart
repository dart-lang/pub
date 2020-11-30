import 'package:args/command_runner.dart';
import 'package:usage/usage.dart';
import 'src/pub_embeddable_command.dart';
export 'src/executable.dart'
    show getExecutableForCommand, CommandResolutionFailedException;

/// Returns a [Command] for pub functionality that can be used by an embedding
/// CommandRunner.
///
/// If [analytics] is given, pub will use that analytics instanve to send
/// statistics about resolutions.
Command<int> pubCommand({Analytics analytics}) =>
    PubEmbeddableCommand(analytics);
