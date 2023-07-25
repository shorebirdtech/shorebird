import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';

/// Wrapper around the `ios-deploy` command cached by the Flutter tool.
/// https://github.com/ios-control/ios-deploy
class IOSDeploy {
  File get _iosDeployExecutable => File(
        p.join(
          ShorebirdEnvironment.flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'ios-deploy',
          'ios-deploy',
        ),
      );

  bool get _isInstalled => _iosDeployExecutable.existsSync();

  /// Installs the .app file at [bundlePath] to the device identified by
  /// [deviceId] and attaches the debugger.
  ///
  /// Uses ios-deploy and returns the exit code.
  /// `ios-deploy --id [deviceId] --debug --bundle [bundlePath]`
  Future<int> installAndLaunchApp({
    required String bundlePath,
    String? deviceId,
  }) async {
    final result = await process.run(
      _iosDeployExecutable.path,
      [
        '--debug',
        if (deviceId != null) ...['--id', deviceId],
        '--bundle',
        bundlePath,
      ],
    );
    return result.exitCode;
  }

  /// Installs ios-deploy if it is not already installed.
  Future<void> installIfNeeded() async {
    if (_isInstalled) return;

    final progress = logger.progress('Installing ios-deploy');

    final result = await process.run('flutter', ['precache', '--ios']);

    if (result.exitCode != ExitCode.success.code || !_isInstalled) {
      const errorMessage = 'Failed to install ios-deploy.';
      progress.fail(errorMessage);
      throw Exception(errorMessage);
    }

    progress.complete();
  }
}
