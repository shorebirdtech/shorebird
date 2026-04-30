import 'dart:io' as io;

import 'package:shorebird_cli/src/json_output.dart';

/// Whether the CLI is running in an interactive context.
///
/// This is the canonical predicate for behaviors that require a TTY:
/// progress spinners, ANSI color output, and interactive prompts
/// (`chooseOne`/`confirm`/`prompt`).
///
/// Returns `false` when any of the following is true:
///   * stdout is not connected to a terminal (`!stdout.hasTerminal`).
///   * `--json` was passed (machine-readable output expected).
bool get isInteractive => io.stdout.hasTerminal && !isJsonMode;

/// The default hint emitted when an interactive prompt is reached in a
/// non-interactive context and no per-site hint was provided.
const String defaultInteractivePromptHint =
    'Re-run with a TTY-attached stdout, or provide the required input via a '
    'command-line flag.';

/// {@template interactive_prompt_required_exception}
/// Thrown when a `confirm`/`chooseOne`/`prompt`/`promptAny` call is reached
/// while the CLI is in a non-interactive context (no TTY or `--json`).
///
/// The runner catches this exception and emits either a JSON error envelope
/// or a verbose human-readable error to stderr.
/// {@endtemplate}
class InteractivePromptRequiredException implements Exception {
  /// {@macro interactive_prompt_required_exception}
  const InteractivePromptRequiredException({
    required this.promptText,
    required this.hint,
  });

  /// The text of the prompt that would have been shown to the user.
  final String promptText;

  /// An actionable recovery hint -- typically the flag the caller could pass
  /// to provide the required input non-interactively.
  final String hint;

  @override
  String toString() =>
      'Interactive input was required but the CLI is running in a '
      'non-interactive context.\n'
      'Prompt: $promptText\n'
      'Hint: $hint';
}
