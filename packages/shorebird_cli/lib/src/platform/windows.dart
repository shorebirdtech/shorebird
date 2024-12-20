import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

String getExeVersionString(File exeFile) {
  final exePath = exeFile.path;
  // r'C:\Users\bryan\Desktop\build\windows\x64\runner\Release\hello_windows.exe';
  final pwshCommand = '(Get-Item -Path $exePath).VersionInfo.ProductVersion';

  final result = process.runSync(
    'powershell.exe',
    ['-Command', pwshCommand],
    runInShell: true,
  );

  if (result.exitCode != ExitCode.success.code) {
    throw Exception('Failed to get version from exe $exePath');
  }

  return (result.stdout as String).trim();
}
