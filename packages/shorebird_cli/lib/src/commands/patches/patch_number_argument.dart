import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// Shared parsing for the patch number option that the `patches`
/// subcommands take.
mixin PatchNumberArgument on ShorebirdCommand {
  /// Resolves the patch number from `--patch-number`, reporting a typo as a
  /// usage error rather than letting it surface as an unhandled
  /// `FormatException`.
  ///
  /// Returns `(patchNumber: <n>, errorCode: null)` on success, or
  /// `(patchNumber: null, errorCode: <code>)` after reporting the failure.
  ({int? patchNumber, int? errorCode}) resolvePatchNumber() {
    const option = CommonArguments.patchNumberArg;
    final arg = results[option.name] as String;
    final patchNumber = int.tryParse(arg);
    if (patchNumber != null) return (patchNumber: patchNumber, errorCode: null);

    final errorCode = reportError(
      message: '"$arg" is not a valid patch number.',
      hint: 'Patch numbers are integers, e.g. --${option.name} 1.',
    );
    return (patchNumber: null, errorCode: errorCode);
  }
}
