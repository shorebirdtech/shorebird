import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/shorebird_engine_mixin.dart';

mixin ShorebirdBuildMixin on ShorebirdEngineMixin {
  Future<void> buildRelease() async {
    const executable = 'flutter';
    final arguments = [
      'build',
      // This is temporary because the Shorebird engine currently
      // only supports Android.
      'appbundle',
      '--release',
      '--local-engine-src-path',
      shorebirdEnginePath,
      '--local-engine',
      // This is temporary because the Shorebird engine currently
      // only supports Android arm64.
      'android_release_arm64',
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
