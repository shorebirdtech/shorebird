import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// The name of the option that gates irreversible deletes.
const confirmNameArgName = 'confirm-name';

/// Shared gate for commands that destroy something irreversibly.
///
/// A prompt cannot run under `--json`, so a prompt-based confirmation would
/// make every delete unreachable to CI and to agents. Requiring the caller to
/// echo the resource's current name behaves identically in both contexts and,
/// unlike a bare `--force`, cannot be satisfied without having resolved the
/// right resource first.
mixin ConfirmNameArgument on ShorebirdCommand {
  /// Verifies that `--confirm-name` matches [expected].
  ///
  /// Returns `null` when the caller may proceed, or an exit code after
  /// reporting why it may not. [resourceDescription] names the thing being
  /// deleted, for the human-readable message.
  int? checkConfirmName({
    required String expected,
    required String resourceDescription,
  }) {
    final provided = results[confirmNameArgName] as String?;
    if (provided == expected) return null;

    final hint = 'Re-run with --$confirmNameArgName="$expected".';
    final message = provided == null
        ? 'Deleting $resourceDescription requires --$confirmNameArgName.'
        : '--$confirmNameArgName "$provided" does not match "$expected".';

    if (isJsonMode) {
      emitJsonError(
        code: JsonErrorCode.usageError,
        message: message,
        hint: hint,
      );
    } else {
      logger
        ..err(message)
        ..info(hint);
    }
    return ExitCode.usage.code;
  }
}
