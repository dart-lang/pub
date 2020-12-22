import 'package:args/command_runner.dart';
import 'src/pub_embeddable_command.dart';
export 'src/executable.dart'
    show getExecutableForCommand, CommandResolutionFailedException;
export 'src/pub_embeddable_command.dart' show PubAnalytics;

/// Returns a [Command] for pub functionality that can be used by an embedding
/// CommandRunner.
///
/// If [analytics] is given, pub will use that analytics instance to send
/// statistics about resolutions.
Command<int> pubCommand({PubAnalytics analytics}) =>
    PubEmbeddableCommand(analytics);
