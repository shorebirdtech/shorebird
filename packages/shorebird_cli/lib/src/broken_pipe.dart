// cspell:words EPIPE epipe
import 'dart:io';

/// The exit code for a process whose stdout reader went away: 128 + SIGPIPE.
///
/// Programs killed by SIGPIPE, such as `git` and `gh` writing into a `head`
/// that has exited, report this status to the shell. The Dart VM ignores
/// SIGPIPE, so the CLI exits with the same status itself.
const brokenPipeExitCode = 141;

// EPIPE on Linux and macOS.
const _epipe = 32;
// ERROR_BROKEN_PIPE and ERROR_NO_DATA on Windows.
const _windowsBrokenPipe = 109;
const _windowsNoData = 232;

/// Whether [error] is a write to a pipe whose reader has closed, as when
/// `shorebird api /apps | head -1` keeps writing after `head` exits.
bool isBrokenPipe(Object error) {
  final osError = switch (error) {
    FileSystemException(:final osError) => osError,
    SocketException(:final osError) => osError,
    _ => null,
  };
  return switch (osError?.errorCode) {
    _epipe || _windowsBrokenPipe || _windowsNoData => true,
    _ => false,
  };
}
