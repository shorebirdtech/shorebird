import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';

/// Wrapper around the `ios-deploy` command cached by the Flutter tool.
/// https://github.com/ios-control/ios-deploy
class IOSDeploy {
  /// Installs the .app file at [bundlePath]
  /// to the device identified by [deviceId]
  /// and attaches the debugger.
  ///
  /// Uses ios-deploy and returns the exit code.
  /// `ios-deploy --id [deviceId] --debug --bundle [bundlePath]`
  Future<int> installAndLaunchApp({
    required String bundlePath,
    String? deviceId,
  }) async {
    final iosDeployExecutable = p.join(
      ShorebirdEnvironment.flutterDirectory.path,
      'bin',
      'cache',
      'artifacts',
      'ios-deploy',
      'ios-deploy',
    );
    final result = await process.run(
      iosDeployExecutable,
      [
        '--debug',
        if (deviceId != null) ...['--id', deviceId],
        '--bundle',
        bundlePath,
      ],
    );
    return result.exitCode;
  }
}
