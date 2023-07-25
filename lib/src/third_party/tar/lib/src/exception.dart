import 'package:meta/meta.dart';

/// An exception indicating that there was an issue parsing a `.tar` file.
///
/// The [message] contains reported from this exception contains details on the
/// location of the parsing error.
///
/// This is the only exception that should be thrown by the `tar` package. Other
/// exceptions are either a bug in this package or errors thrown as a response
/// to API misuse.
final class TarException extends FormatException {
  @internal
  TarException(String message) : super(message);

  @internal
  factory TarException.header(String message) {
    return TarException('Invalid header: $message');
  }
}
