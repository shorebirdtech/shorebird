# cli_io

I/O utilities for Shorebird's CLI tools.

Provides:

- `Logger` — leveled logging (`info`, `err`, `warn`, `detail`, `success`) with
  optional ANSI styling.
- `Progress` — animated progress indicator for long-running operations.
- `prompt`, `confirm`, `chooseOne` — interactive input helpers.
- `Level` — log-level enum.
- `ExitCode` — standard CLI exit codes (sysexits.h).
- `link` — OSC-8 hyperlink helper.
- ANSI color and style constants.

## Lineage

The public API is modeled after [`mason_logger`][mason_logger], which
Shorebird depended on historically. When we replaced that dependency with our
own implementation, we kept method names and signatures intentionally
compatible so existing call sites only needed to change their import from
`package:mason_logger/mason_logger.dart` to `package:cli_io/cli_io.dart`.

This is a clean-room implementation, not a fork — none of mason_logger's
source is vendored. The API is a starting point, not a contract; we expect
it to evolve over time as Shorebird's CLI tooling needs change (for example,
adding structured/JSON output for agentic consumers, or splitting out a
separate logger for server-side code).

## Notable differences from mason_logger

- `chooseOne` is a numbered prompt (e.g. `Enter selection (1-3):`) rather
  than an arrow-key-driven selector. No FFI, no raw-mode terminal handling,
  works over SSH and in CI.
- Omits APIs we don't use: `chooseAny`, `promptAny`, `alert`, `delayed`,
  `flush`, `LogTheme` configuration, hidden-input prompts, and the keyboard
  primitives (`KeyStroke`, `ControlCharacter`, `TerminalOverrides`).
- `ExitCode` and ANSI color/style constants are inlined here rather than
  re-exported from `package:io`.

[mason_logger]: https://pub.dev/packages/mason_logger
