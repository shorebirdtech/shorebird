import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// The name of the flag that pauses for confirmation before publishing.
const confirmArgName = 'confirm';

/// The prompt shown before publishing when `--confirm` is passed.
const confirmBeforePublishPrompt = 'Would you like to continue?';

/// The hint reported when `--confirm` is passed but the CLI cannot prompt.
const confirmBeforePublishHint =
    'Re-run in a terminal to confirm before publishing, or without '
    '--$confirmArgName to publish without pausing.';

/// The opt-in `--confirm` pause before `release` and `patch` publish.
///
/// Without `--confirm` (the default) nothing is asked. With it, the command
/// shows its summary and asks before publishing. When the CLI cannot prompt,
/// [assertCanConfirmBeforePublish] fails before any build work starts.
mixin ConfirmBeforePublish on ShorebirdCommand {
  /// Adds the hidden `--confirm` flag.
  void addConfirmBeforePublishFlag() {
    // Added for https://github.com/shorebirdtech/shorebird/issues/3223.
    // Can be removed fall 2026 or later.
    argParser.addFlag(confirmArgName, hide: true);
  }

  /// Whether to pause for confirmation before publishing.
  bool get confirm => results[confirmArgName] == true;

  /// Throws [InteractivePromptRequiredException] when `--confirm` was passed
  /// but the CLI cannot prompt, so the command fails before building rather
  /// than at the pause.
  void assertCanConfirmBeforePublish() {
    if (!confirm || shorebirdEnv.canAcceptUserInput) return;
    throw const InteractivePromptRequiredException(
      promptText: confirmBeforePublishPrompt,
      hint: confirmBeforePublishHint,
    );
  }

  /// When `--confirm` was passed, asks whether to continue, and throws
  /// [PromptDeclinedExit] if the user declines.
  void confirmBeforePublish() {
    if (!confirm) return;
    if (logger.confirm(confirmBeforePublishPrompt, defaultValue: true)) return;
    logger.err('Aborting.');
    throw PromptDeclinedExit();
  }
}
