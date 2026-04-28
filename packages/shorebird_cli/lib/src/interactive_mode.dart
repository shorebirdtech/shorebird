import 'dart:io' as io;

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/json_output.dart';

/// A reference to whether non-interactive mode (`--no-input`) is active.
final isNoInputModeRef = create(() => false);

/// Whether non-interactive mode (`--no-input`) is active in the current zone.
bool get isNoInputMode => read(isNoInputModeRef);

/// Whether the CLI is running in an interactive context.
///
/// This is the canonical predicate for behaviors that require a TTY:
/// progress spinners, ANSI color output, and interactive prompts
/// (`chooseOne`/`confirm`/`prompt`).
///
/// Returns `false` when any of the following is true:
///   * stdout is not connected to a terminal (`!stdout.hasTerminal`).
///   * `--json` was passed (machine-readable output expected).
///   * `--no-input` was passed (explicit non-interactive opt-in).
bool get isInteractive =>
    io.stdout.hasTerminal && !isJsonMode && !isNoInputMode;
