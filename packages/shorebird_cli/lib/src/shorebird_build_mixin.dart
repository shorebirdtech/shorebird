import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';

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

/// {@template build_exception}
/// Thrown when a build fails.
/// {@endtemplate}
class BuildException implements Exception {
  /// {@macro build_exception}
  BuildException(this.message);

  /// Information about the build failure.
  final String message;
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

  Future<void> buildAppBundle({String? flavor, String? target}) async {
    const executable = 'flutter';
    final arguments = [
      'build',
      'appbundle',
      '--release',
      if (flavor != null) '--flavor=$flavor',
      if (target != null) '--target=$target',
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

  Future<void> buildAar({
    required String buildNumber,
    String? flavor,
  }) async {
    const executable = 'flutter';
    final arguments = [
      'build',
      'aar',
      '--no-debug',
      '--no-profile',
      '--build-number=$buildNumber',
      if (flavor != null) '--flavor=$flavor',
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

  Future<void> buildApk({String? flavor, String? target}) async {
    const executable = 'flutter';
    final arguments = [
      'build',
      'apk',
      '--release',
      if (flavor != null) '--flavor=$flavor',
      if (target != null) '--target=$target',
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

  Future<void> buildIpa({
    String? flavor,
    String? target,
    bool codesign = true,
  }) async {
    const executable = 'flutter';
    final exportPlistFile = _createExportOptionsPlist();
    final arguments = [
      'build',
      'ipa',
      '--release',
      '--export-options-plist=${exportPlistFile.path}',
      if (flavor != null) '--flavor=$flavor',
      if (target != null) '--target=$target',
      if (!codesign) '--no-codesign',
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
    } else if (result.stderr
        .toString()
        .contains('Encountered error while creating the IPA')) {
      final errorMessage = _failedToCreateIpaErrorMessage(
        stderr: result.stderr.toString(),
      );

      throw BuildException(errorMessage);
    }
  }

  /// Creates an ExportOptions.plist file, which is used to tell xcodebuild to
  /// not manage the app version and build number. If we don't do this, then
  /// xcodebuild will increment the build number if it detects an App Store
  /// Connect build with the same version and build number.
  /// See
  /// https://developer.apple.com/forums/thread/690647?answerId=689925022#689925022
  File _createExportOptionsPlist() {
    const plistContents = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
  <key>signingStyle</key>
	<string>automatic</string>
  <key>uploadBitcode</key>
  <false/>
  <key>method</key>
  <string>app-store</string>
</dict>
</plist>
''';
    final tempDir = Directory.systemTemp.createTempSync();
    final exportPlistFile = File(p.join(tempDir.path, 'ExportOptions.plist'))
      ..createSync(recursive: true)
      ..writeAsStringSync(plistContents);
    return exportPlistFile;
  }

  String _failedToCreateIpaErrorMessage({required String stderr}) {
    // The full error text consists of many repeated lines of the format:
    // (newlines added for line length)
    //
    //    error: exportArchive: No signing certificate "iOS Distribution" found
    //    error: exportArchive: Communication with Apple failed
    //    error: exportArchive: No signing certificate "iOS Distribution" found
    //    error: exportArchive: Team "My Team" does not have permission to
    //      create "iOS App Store" provisioning profiles.
    //    error: exportArchive: No profiles for 'com.example.demo' were found
    //    error: exportArchive: Communication with Apple failed
    //    error: exportArchive: No signing certificate "iOS Distribution" found
    //    error: exportArchive: Communication with Apple failed
    final exportArchiveRegex = RegExp(r'^error: exportArchive: (.+)$');

    return stderr
        .split('\n')
        .map((l) => l.trim())
        .toSet()
        .map(exportArchiveRegex.firstMatch)
        .whereType<Match>()
        .map((m) => '    ${m.group(1)!}')
        .join('\n');
  }

  Future<String> createDiff({
    required String releaseArtifactPath,
    required String patchArtifactPath,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp();
    final diffPath = p.join(tempDir.path, 'diff.patch');
    final diffExecutable = p.join(
      cache.getArtifactDirectory('patch').path,
      'patch',
    );
    final diffArguments = [
      releaseArtifactPath,
      patchArtifactPath,
      diffPath,
    ];

    final result = await process.run(
      diffExecutable,
      diffArguments,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to create diff: ${result.stderr}');
    }

    return diffPath;
  }

  /// Creates an AOT snapshot of the given [appDillPath] and returns the
  /// resulting snapshot file.
  // TODO(bryanoltman): make this work with the --local-engine flag.
  Future<File> buildElfAotSnapshot({required String appDillPath}) async {
    final outFilePath = p.join(Directory.current.path, 'build', 'out.aot');
    final arguments = [
      '--deterministic',
      '--snapshot-kind=app-aot-elf',
      '--elf=$outFilePath',
      appDillPath
    ];

    final result = await process.run(
      ShorebirdEnvironment.genSnapshotFile.path,
      arguments,
    );

    if (result.exitCode != ExitCode.success.code) {
      throw Exception('Failed to create snapshot: ${result.stderr}');
    }

    return File(outFilePath);
  }
}
