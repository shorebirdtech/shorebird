import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [Powershell] instance.
final powershellRef = create(Powershell.new);

/// The [Powershell] instance available in the current zone.
Powershell get powershell => read(powershellRef);

/// A wrapper around all powershell related functionality.
class Powershell {
  /// Name of the powershell executable.
  static const executable = 'powershell.exe';

  /// Execute a powershell command with the provided [arguments].
  Future<ShorebirdProcessResult> pwsh(
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    final result = await process.run(
      executable,
      arguments,
      runInShell: true,
    );
    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    return result;
  }

  /// Returns the version string of the given executable file.
  Future<String> getExeVersionString(File exeFile) async {
    final exePath = exeFile.path;
    final pwshCommand = '(Get-Item -Path $exePath).VersionInfo.ProductVersion';

    final result = await pwsh(
      ['-Command', pwshCommand],
      runInShell: true,
    );

    return (result.stdout as String).trim();
  }
}
