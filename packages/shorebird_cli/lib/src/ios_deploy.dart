import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';

/// Wrapper around the `ios-deploy` command cached by the Flutter tool.
/// https://github.com/ios-control/ios-deploy
class IOSDeploy {
  /// Installs the .app file at [bundlePath] to the device identified by [deviceId].
  ///
  /// Uses ios-deploy and returns the exit code.
  /// `ios-deploy --id [deviceId] --bundle [bundlePath]`
  Future<int> installApp({
    required String deviceId,
    required String bundlePath,
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
        '--id',
        deviceId,
        '--bundle',
        bundlePath,
      ],
    );
    return result.exitCode;
  }
}
