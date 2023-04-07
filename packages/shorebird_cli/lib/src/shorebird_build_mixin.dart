import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';

mixin ShorebirdBuildMixin on ShorebirdCommand {
  Future<void> buildRelease() async {
    const executable = 'flutter';
    final arguments = [
      'build',
      // This is temporary because the Shorebird engine currently
      // only supports Android.
      'appbundle',
      '--release',
      ...results.rest,
    ];

    final result = await runProcess(
      executable,
      arguments,
      runInShell: true,
    );

    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(
        'flutter',
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}
