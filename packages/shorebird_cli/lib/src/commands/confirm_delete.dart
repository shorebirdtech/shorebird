import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// The name of the flag that skips the delete confirmation prompt.
const yesArgName = 'yes';

/// The name of the deprecated option that used to confirm deletes by echoing
/// the resource's name. Still accepted so existing scripts keep working.
const confirmNameArgName = 'confirm-name';

/// The message reported when a delete needs confirmation but cannot prompt.
const yesRequiredMessage =
    '--$yesArgName required when not running interactively';

/// How a delete is confirmed when the CLI can prompt.
enum DeleteConfirmationStyle {
  /// Ask a y/N question, like `gh release delete`.
  yesNo,

  /// Make the user type the resource's name, like `gh repo delete`.
  typeName,
}

/// Shared confirmation for commands that delete something irreversibly.
///
/// Follows the GitHub CLI's convention: `-y, --yes` skips confirmation; in a
/// terminal the user is prompted; without one (stdin or stdout not a
/// terminal, CI, or `--json`) the command fails with "--yes required when not
/// running interactively" rather than waiting for input.
mixin ConfirmDelete on ShorebirdCommand {
  /// Adds `-y, --yes` and the hidden, deprecated `--confirm-name`.
  void addConfirmDeleteOptions() {
    argParser
      ..addFlag(
        yesArgName,
        abbr: 'y',
        negatable: false,
        help: 'Skip the confirmation prompt.',
      )
      ..addOption(
        confirmNameArgName,
        hide: true,
        help: 'Deprecated: use --$yesArgName.',
      );
  }

  /// Confirms deleting [description], whose name is [name].
  ///
  /// Returns `null` when the caller may proceed, or an exit code after
  /// reporting why it may not.
  int? confirmDelete({
    required String name,
    required String description,
    required DeleteConfirmationStyle style,
  }) {
    final hint = 'Re-run with --$yesArgName to delete $description.';
    final confirmName = results[confirmNameArgName] as String?;
    if (confirmName != null) {
      logger.warn(
        '--$confirmNameArgName is deprecated and will be removed; use '
        '--$yesArgName instead.',
      );
      if (confirmName == name) return null;
      return reportError(
        message: '--$confirmNameArgName "$confirmName" does not match "$name".',
        hint: hint,
      );
    }

    if (results[yesArgName] == true) return null;

    // Both stdin and stdout must be terminals to prompt; otherwise every
    // non-interactive case gets the same message, before anything is printed.
    if (!isInteractive || !shorebirdEnv.canAcceptUserInput) {
      return reportError(message: yesRequiredMessage, hint: hint);
    }

    switch (style) {
      case DeleteConfirmationStyle.yesNo:
        if (logger.confirm('Delete $description?', hint: hint)) return null;
        logger.info('Nothing was deleted.');
        return ExitCode.success.code;
      case DeleteConfirmationStyle.typeName:
        logger.info('This permanently deletes $description.');
        final typed = logger
            .prompt('Type $name to confirm deletion:', hint: hint)
            .trim();
        if (typed == name) return null;
        return reportError(
          message: '"$typed" does not match "$name". Nothing was deleted.',
        );
    }
  }
}
