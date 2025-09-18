import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/windows/windows_exe_selector.dart';

/// Returns the Windows application ProductVersion for the app executable in
/// [releaseDir]. Uses [projectNameHint] to disambiguate if multiple `.exe`
/// files are present. Logs helpful details with the provided [logTag].
Future<String> getWindowsAppVersionFromDir(
  Directory releaseDir, {
  String? projectNameHint,
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
    ..detail('[$logTag] projectName: ${projectNameHint ?? '(unknown)'}');

  final exeFile = selectWindowsAppExe(
    releaseDir,
    projectNameHint: projectNameHint,
  );
  logger.detail('[$logTag] Selected exe: ${exeFile.path}');

  return powershell.getExeVersionString(exeFile);
}
