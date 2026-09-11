import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// Shared parsing for the `--patch-number` option that the `patches`
/// subcommands take.
mixin PatchNumberArgument on ShorebirdCommand {
  /// Resolves `--patch-number`, reporting a typo as a usage error rather than
  /// letting it surface as an unhandled `FormatException`.
  ///
  /// Returns `(patchNumber: <n>, errorCode: null)` on success, or
  /// `(patchNumber: null, errorCode: <code>)` after reporting the failure.
  ({int? patchNumber, int? errorCode}) resolvePatchNumber() {
    final arg = results['patch-number'] as String;
    final patchNumber = int.tryParse(arg);
    if (patchNumber != null) return (patchNumber: patchNumber, errorCode: null);

    const hint = 'Patch numbers are integers, e.g. --patch-number 1.';
    if (isJsonMode) {
      emitJsonError(
        code: JsonErrorCode.usageError,
        message: '"$arg" is not a valid patch number.',
        hint: hint,
      );
    } else {
      logger
        ..err('"$arg" is not a valid patch number')
        ..info(hint);
    }
    return (patchNumber: null, errorCode: ExitCode.usage.code);
  }
}
