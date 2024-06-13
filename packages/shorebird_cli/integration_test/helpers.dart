import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

/// Helper function to run a command in the shell, meant to be used in tests.
///
/// It will take a command string, like `shorebird --version`, run it in the
/// shell, and return the result.
ProcessResult runCommand(
  String command, {
  required String workingDirectory,
  Logger? logger,
}) {
  final parts = command.split(' ');
  final executable = parts.first;
  final arguments = parts.skip(1).toList();
  (logger ?? Logger()).info('running $command in $workingDirectory');
  return Process.runSync(
    executable,
    arguments,
    runInShell: true,
    workingDirectory: workingDirectory,
  );
}
