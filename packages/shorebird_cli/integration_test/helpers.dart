import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

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
