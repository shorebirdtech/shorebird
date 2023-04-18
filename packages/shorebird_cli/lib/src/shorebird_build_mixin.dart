import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';

enum Arch {
  arm64,
  arm32,
  x86,
}

class ArchMetadata {
  const ArchMetadata({required this.path, required this.arch});

  final String path;
  final String arch;
}

mixin ShorebirdBuildMixin on ShorebirdCommand {
  // TODO(felangel): extend to other platforms.
  static const architectures = <Arch, ArchMetadata>{
    Arch.arm64: ArchMetadata(
      path: 'arm64-v8a',
      arch: 'aarch64',
    ),
    Arch.arm32: ArchMetadata(
      path: 'armeabi-v7a',
      arch: 'arm',
    ),
    Arch.x86: ArchMetadata(
      path: 'x86_64',
      arch: 'x86_64',
    ),
  };

  Future<void> buildAppBundle() async {
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

  Future<void> buildApk() async {
    const executable = 'flutter';
    final arguments = [
      'build',
      // This is temporary because the Shorebird engine currently
      // only supports Android.
      'apk',
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
