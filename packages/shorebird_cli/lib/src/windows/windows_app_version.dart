import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/windows/windows_exe_selector.dart';

/// Returns the Windows application ProductVersion for the .exe in [releaseDir].
/// Uses [projectName] (the pubspec name) to select the exe: prefers an exact
/// match on '[projectName].exe', then a filename containing '[projectName]',
/// otherwise falls back to the first .exe. Logs details with [logTag].
/// [releaseDir] is the directory containing the release artifacts. In the
/// release flow, [WindowsReleaser.getReleaseVersion()] passes the [Directory]
/// returned by [artifactBuilder.buildWindowsApp()] directly here.
/// Only top-level .exe files in [releaseDir] are considered (non-recursive).
Future<String> getWindowsAppVersionFromDir(
  Directory releaseDir, {
  String? projectName,
  String logTag = 'windows',
}) async {
  final exesFound = releaseDir
      .listSync()
      .whereType<File>()
      .where((f) => p.extension(f.path).toLowerCase() == '.exe')
      .map((f) => p.basename(f.path))
      .toList();

  logger
    ..detail('[$logTag] EXEs found in directory: ${exesFound.join(', ')}')
    ..detail('[$logTag] projectName: ${projectName ?? '(unknown)'}');

  final exeFile = selectWindowsAppExe(
    releaseDir,
    projectName: projectName,
  );
  logger.detail('[$logTag] Selected exe: ${exeFile.path}');

  return powershell.getExeVersionString(exeFile);
}
