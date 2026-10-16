import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// The name of the flag that skips the delete confirmation prompt.
const yesArgName = 'yes';

/// The name of the option that confirms a delete by giving the resource's
/// name. Required for [DeleteConfirmationStyle.typeName] deletes when not
/// running interactively; a hidden, deprecated alternative to `--yes`
/// otherwise.
const confirmNameArgName = 'confirm-name';

/// The message reported when a delete needs confirmation but cannot prompt.
const yesRequiredMessage =
    '--$yesArgName required when not running interactively';

/// The message reported when a [DeleteConfirmationStyle.typeName] delete
/// needs the resource's name but cannot prompt.
const confirmNameRequiredMessage =
    '--$confirmNameArgName required when not running interactively';

/// How a delete is confirmed.
enum DeleteConfirmationStyle {
  /// Ask a y/N question, like `gh release delete`. `-y, --yes` skips it.
  yesNo,

  /// Make the user type the resource's name, like `gh repo delete`. There is
  /// no `--yes`: scripts pass the name with `--confirm-name`, so nothing is
  /// deleted without naming it.
  typeName,
}

/// Shared confirmation for commands that delete something irreversibly.
///
/// Follows the GitHub CLI's convention: in a terminal the user is prompted;
/// without one (stdin or stdout not a terminal, CI, or `--json`) the command
/// fails rather than waiting for input. A [DeleteConfirmationStyle.yesNo]
/// delete is confirmed non-interactively with `-y, --yes`; a
/// [DeleteConfirmationStyle.typeName] delete only with `--confirm-name` set to
/// the resource's name.
mixin ConfirmDelete on ShorebirdCommand {
  late final DeleteConfirmationStyle _deleteConfirmationStyle;

  /// Adds the options that confirm a delete in [style].
  ///
  /// [DeleteConfirmationStyle.yesNo] adds `-y, --yes` and a hidden, deprecated
  /// `--confirm-name`. [DeleteConfirmationStyle.typeName] adds only
  /// `--confirm-name`, which [nameDescription] describes (e.g. "The app's
  /// display name").
  void addConfirmDeleteOptions({
    DeleteConfirmationStyle style = DeleteConfirmationStyle.yesNo,
    String nameDescription = 'The name',
  }) {
    _deleteConfirmationStyle = style;
    switch (style) {
      case DeleteConfirmationStyle.yesNo:
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
      case DeleteConfirmationStyle.typeName:
        argParser.addOption(
          confirmNameArgName,
          valueHelp: 'name',
          help:
              '$nameDescription, to confirm the delete without a prompt. '
              'Required when not running interactively.',
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
    return switch (_deleteConfirmationStyle) {
      DeleteConfirmationStyle.yesNo => _confirmYesNo(
        name,
        description,
        consequence,
      ),
      DeleteConfirmationStyle.typeName => _confirmTypeName(
        name,
        description,
        consequence,
      ),
    };
  }

  int? _confirmYesNo(String name, String description, String consequence) {
    final hint = 'Re-run with --$yesArgName to delete $description.';
    final confirmName = results[confirmNameArgName] as String?;
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

    if (!_canPrompt) {
      return reportError(message: yesRequiredMessage, hint: hint);
    }

    _announce(consequence);
    if (logger.confirm('Delete $description?', hint: hint)) return null;
    logger.err('Nothing was deleted.');
    throw PromptDeclinedExit();
  }

  int? _confirmTypeName(
    String name,
    String description,
    String consequence,
  ) {
    final hint =
        'Re-run with --$confirmNameArgName "$name" to delete $description.';
    final confirmName = results[confirmNameArgName] as String?;
    if (confirmName != null) {
      if (confirmName == name) return _announce(consequence);
      return reportError(
        message: '--$confirmNameArgName "$confirmName" does not match "$name".',
        hint: hint,
      );
    }

    if (!_canPrompt) {
      return reportError(message: confirmNameRequiredMessage, hint: hint);
    }

    _announce(consequence);
    final typed = logger
        .prompt('Type $name to confirm deletion:', hint: hint)
        .trim();
    if (typed == name) return null;
    logger.err('"$typed" does not match "$name". Nothing was deleted.');
    throw PromptDeclinedExit();
  }

  /// Prints [consequence] in text mode and returns null, so a confirmed delete
  /// can `return _announce(...)`.
  int? _announce(String consequence) {
    if (!isJsonMode) logger.info(consequence);
    return null;
  }

  // Every case where the CLI cannot prompt gets the same message, before
  // anything is printed.
  bool get _canPrompt => shorebirdEnv.canAcceptUserInput;
}
