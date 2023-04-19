import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';

enum Arch {
  arm64,
  arm32,
  x86_64,
}

class ArchMetadata {
  const ArchMetadata({
    required this.path,
    required this.arch,
    required this.enginePath,
  });

  final String path;
  final String arch;
  final String enginePath;
}

mixin ShorebirdBuildMixin on ShorebirdCommand {
  // This exists only so tests can get the full list.
  static const allAndroidArchitectures = <Arch, ArchMetadata>{
    Arch.arm64: ArchMetadata(
      path: 'arm64-v8a',
      arch: 'aarch64',
      enginePath: 'android_release_arm64',
    ),
    Arch.arm32: ArchMetadata(
      path: 'armeabi-v7a',
      arch: 'arm',
      enginePath: 'android_release',
    ),
    Arch.x86_64: ArchMetadata(
      path: 'x86_64',
      arch: 'x86_64',
      enginePath: 'android_release_x64',
    ),
  };

  // TODO(felangel): extend to other platforms.
  Map<Arch, ArchMetadata> get architectures {
    // Flutter has a whole bunch of logic to parse the --local-engine flag.
    // We probably need similar.
    // It's a bit odd to grab off the shorebird process, but it's the easiest
    // way to have a single source of truth for the engine config for now.
    if (engineConfig.localEngine != null) {
      final localEngineOutName = engineConfig.localEngine;
      final metaDataEntry = allAndroidArchitectures.entries.firstWhereOrNull(
        (entry) => localEngineOutName == entry.value.enginePath,
      );
      if (metaDataEntry == null) {
        throw Exception(
          'Unknown local engine architecture for '
          '--local-engine=$localEngineOutName\n'
          'Known values: '
          '${allAndroidArchitectures.values.map((e) => e.enginePath)}',
        );
      }
      return {metaDataEntry.key: metaDataEntry.value};
    }
    return allAndroidArchitectures;
  }

  Future<void> buildAppBundle() async {
    const executable = 'flutter';
    final arguments = [
      'build',
      'appbundle',
      '--release',
      ...results.rest,
    ];

    final result = await process.run(
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
      'apk',
      '--release',
      ...results.rest,
    ];

    final result = await process.run(
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
