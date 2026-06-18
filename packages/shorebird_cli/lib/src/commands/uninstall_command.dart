import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// {@template uninstall_command}
/// `shorebird uninstall`
/// Uninstalls Shorebird from the system and removes it from the path.
/// {@endtemplate}
class UninstallCommand extends ShorebirdCommand {
  /// {@macro uninstall_command}
  UninstallCommand();

  @override
  String get description => 'Uninstall Shorebird from the system.';

  /// Name of the command, exposed for the [CommandRunner].
  static const String commandName = 'uninstall';

  @override
  String get name => commandName;

  @override
  Future<int> run() async {
    final confirm = logger.confirm('Are you sure you want to uninstall Shorebird?');
    if (!confirm) {
      logger.info('Aborting.');
      return ExitCode.success.code;
    }

    final progress = logger.progress('Uninstalling Shorebird');

    try {
      if (platform.isWindows) {
        // Remove from PATH on Windows
        final path = platform.environment['Path'] ?? '';
        final newPath = path
            .split(Platform.pathSeparator)
            .where((pathSegment) => !pathSegment.contains(r'.shorebird\bin'))
            .join(Platform.pathSeparator);
        
        await Process.run('powershell.exe', [
          '-Command',
          '[Environment]::SetEnvironmentVariable("Path", "$newPath", "User")',
        ]);

        // We use a detached process to delete the shorebird directory because
        // the current process is running from within the directory.
        await Process.start(
          'powershell.exe',
          [
            '-Command',
            'Start-Sleep -Seconds 1; Remove-Item -Recurse -Force "${shorebirdEnv.shorebirdRoot.path}"'
          ],
          mode: ProcessStartMode.detached,
        );
      } else {
        // Remove from rc files on Mac/Linux
        final home = platform.environment['HOME'] ?? '';
        if (home.isNotEmpty) {
          final rcFiles = [
            File(p.join(home, '.bashrc')),
            File(p.join(home, '.zshrc')),
            File(p.join(home, '.bash_profile')),
            File(p.join(home, '.profile')),
          ];

          for (final file in rcFiles) {
            if (file.existsSync()) {
              final lines = file.readAsLinesSync();
              final newLines = lines.where((line) => !line.contains('.shorebird/bin')).toList();
              if (lines.length != newLines.length) {
                file.writeAsStringSync('${newLines.join('\n')}\n');
              }
            }
          }
        }

        shorebirdEnv.shorebirdRoot.deleteSync(recursive: true);
      }
    } catch (error) {
      progress.fail();
      logger.err('Failed to uninstall Shorebird: $error');
      return ExitCode.software.code;
    }

    progress.complete('Shorebird has been uninstalled.');
    logger.info('Please restart your terminal for the PATH changes to take effect.');
    
    return ExitCode.success.code;
  }
}
