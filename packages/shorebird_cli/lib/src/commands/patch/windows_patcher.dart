import 'dart:io';

import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive_analysis/windows_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/commands/patch/desktop_patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// {@template windows_patcher}
/// Functions to create a Windows patch.
/// {@endtemplate}
class WindowsPatcher extends DesktopPatcher {
  /// {@macro windows_patcher}
  WindowsPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.windows;

  @override
  List<Validator> get commandValidators => doctor.windowsCommandValidators;

  @override
  String get hostOperatingSystem => NativePlatform.windows;

  @override
  WindowsArchiveDiffer get archiveDiffer => const WindowsArchiveDiffer();

  /// The release artifact is the zipped directory at
  /// build/windows/x64/runner/Release.
  @override
  Directory get appDirectory => artifactManager.getWindowsReleaseDirectory();

  @override
  List<String> get dartLibraryPathSegments => const ['data', 'app.so'];

  @override
  Future<Directory> buildApp({
    required List<String> args,
    String? base64PublicKey,
  }) {
    return artifactBuilder.buildWindowsApp(
      target: target,
      args: args,
      base64PublicKey: base64PublicKey,
    );
  }

  @override
  Future<String> versionFromAppDirectory(Directory appDirectory) {
    final executable = windows.findExecutable(
      releaseDirectory: appDirectory,
      projectName: shorebirdEnv.getPubspecYaml()!.name,
    );
    return powershell.getProductVersion(executable);
  }
}
