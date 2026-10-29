import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

/// Matches a [PromptDeclinedExit], thrown when the user declines a
/// confirmation prompt.
final Matcher exitsDeclined = throwsA(
  isA<PromptDeclinedExit>().having(
    (e) => e.exitCode,
    'exitCode',
    declinedExitCode,
  ),
);

Matcher exitsWithCode(ExitCode exitcode) => throwsA(
  isA<ProcessExit>().having((e) => e.exitCode, 'exitCode', exitcode.code),
);

/// Matches a [CommandError] whose message is [message] and whose exit code is
/// [exitCode], and, when given, whose hint is [hint]. [message] and [hint]
/// may be matchers, such as `contains('...')`.
Matcher exitsWithError({
  required Object message,
  Object? hint,
  ExitCode exitCode = ExitCode.usage,
}) => throwsA(isCommandError(message: message, hint: hint, exitCode: exitCode));

/// Matches a [CommandError] as [exitsWithError] does, for use where the
/// error itself is checked (such as `throwsA` on a nested future).
Matcher isCommandError({
  required Object message,
  Object? hint,
  ExitCode exitCode = ExitCode.usage,
}) {
  var matcher = isA<CommandError>()
      .having((e) => e.message, 'message', message)
      .having((e) => e.exitCode, 'exitCode', exitCode.code);
  if (hint != null) matcher = matcher.having((e) => e.hint, 'hint', hint);
  return matcher;
}
