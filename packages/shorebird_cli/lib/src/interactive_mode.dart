import 'dart:io' as io;

import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// Whether the CLI is running in an interactive context.
///
/// This is the predicate for output that wants a TTY: progress spinners and
/// ANSI color. Whether the CLI can prompt is a stricter question, answered by
/// `ShorebirdEnv.canAcceptUserInput`.
///
/// Returns `false` when any of the following is true:
///   * stdout is not connected to a terminal.
///   * `--json` was passed (machine-readable output expected).
///
/// `Stdout.hasTerminal` is winsize-based, not isatty-based, so PTYs with
/// default 0x0 winsize fail it. `stdioType(stdout) == StdioType.terminal`
/// catches them. It is broader than isatty: it reports any character device
/// as a terminal, including `/dev/null`.
bool get isInteractive {
  if (isJsonMode) return false;
  if (io.stdout.hasTerminal) return true;
  return io.stdioType(io.stdout) == io.StdioType.terminal;
}

/// The exit code when the user declines a confirmation prompt.
///
/// A declined prompt means the command did not do what was asked, so it must
/// not report success to scripts and agents. 1 is the common convention for an
/// aborted command (terraform, apt-get and gcloud all exit 1).
const int declinedExitCode = 1;

/// {@template prompt_declined_exit}
/// A [ProcessExit] thrown when the user declines a confirmation prompt.
///
/// The command has already said what it did not do (e.g. "Aborting."), so the
/// runner exits with [declinedExitCode] without the "re-run with --verbose"
/// footer it prints after unexplained failures.
/// {@endtemplate}
class PromptDeclinedExit extends ProcessExit {
  /// {@macro prompt_declined_exit}
  PromptDeclinedExit() : super(declinedExitCode);
}

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
