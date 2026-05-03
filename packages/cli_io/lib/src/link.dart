import 'package:cli_io/src/ansi.dart';

/// Wraps [uri] in an OSC-8 hyperlink escape sequence.
///
/// Terminals that support OSC-8 will render the result as a clickable link
/// showing [message] (or [uri] if [message] is null). When ANSI output is
/// disabled, falls back to a markdown-style `[message](uri)` rendering.
String link({required Uri uri, String? message}) {
  if (!ansiOutputEnabled) {
    return message != null ? '[$message]($uri)' : uri.toString();
  }
  const lead = '\x1B]8;;';
  const tail = '\x1B\\';
  return '$lead$uri$tail${message ?? uri}$lead$tail';
}
