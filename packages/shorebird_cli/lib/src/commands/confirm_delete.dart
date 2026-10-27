import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// The name of the flag that skips the delete confirmation prompt.
const yesArgName = 'yes';

/// The name of the hidden, deprecated alternative to `--yes`, which confirms
/// a delete by giving the resource's name.
const confirmNameArgName = 'confirm-name';

/// The message reported when a delete needs confirmation but cannot prompt.
const yesRequiredMessage =
    '--$yesArgName required when not running interactively';

/// Shared confirmation for commands that delete something irreversibly.
///
/// Follows the GitHub CLI's convention: in a terminal the user is asked a y/N
/// question, like `gh release delete`; without one (stdin or stdout not a
/// terminal, CI, or `--json`) the command fails rather than waiting for
/// input, and `-y, --yes` confirms the delete instead.
///
/// Deletes that ADR-0026 keeps out of the CLI (apps, accounts, teams) use
/// `FinishInConsole` instead.
mixin ConfirmDelete on ShorebirdCommand {
  /// Adds `-y, --yes` and, unless [deprecatedConfirmName] is false (as for
  /// commands that never had it), a hidden, deprecated `--confirm-name`.
  void addConfirmDeleteOptions({bool deprecatedConfirmName = true}) {
    argParser.addFlag(
      yesArgName,
      abbr: 'y',
      negatable: false,
      help: 'Skip the confirmation prompt.',
    );
    if (deprecatedConfirmName) {
      argParser.addOption(
        confirmNameArgName,
        hide: true,
        help: 'Deprecated: use --$yesArgName.',
      );
    }
  }

  /// Confirms deleting [description], whose name is [name].
  ///
  /// [consequence] says what deleting removes. In text mode it is printed
  /// before prompting, and before proceeding when a flag confirmed the delete,
  /// so the user always sees it. With `--json` it is not printed, so stdout
  /// stays a single envelope.
  ///
  /// Returns `null` when the caller may proceed, or an exit code after
  /// reporting why it may not. Throws [PromptDeclinedExit] when the user
  /// declines the prompt.
  int? confirmDelete({
    required String name,
    required String description,
    required String consequence,
  }) {
    final hint = 'Re-run with --$yesArgName to delete $description.';
    final confirmName = argParser.options.containsKey(confirmNameArgName)
        ? results[confirmNameArgName] as String?
        : null;
    if (confirmName != null) {
      logger.warn(
        '--$confirmNameArgName is deprecated and will be removed; use '
        '--$yesArgName instead.',
      );
      if (confirmName == name) return _announce(consequence);
      return reportError(
        message: '--$confirmNameArgName "$confirmName" does not match "$name".',
        hint: hint,
      );
    }

    if (results[yesArgName] == true) return _announce(consequence);

    if (!shorebirdEnv.canAcceptUserInput) {
      return reportError(message: yesRequiredMessage, hint: hint);
    }

    _announce(consequence);
    if (logger.confirm('Delete $description?', hint: hint)) return null;
    logger.err('Nothing was deleted.');
    throw PromptDeclinedExit();
  }

  /// Prints [consequence] in text mode and returns null, so a confirmed delete
  /// can `return _announce(...)`.
  int? _announce(String consequence) {
    if (!isJsonMode) logger.info(consequence);
    return null;
  }
}
