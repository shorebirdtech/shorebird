import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/version.dart';

/// {@template doctor_command}
/// `shorebird doctor`
/// A command that checks for potential issues with the current shorebird
/// environment.
/// {@endtemplate}
class DoctorCommand extends ShorebirdCommand {
  /// {@macro doctor_command}
  DoctorCommand() {
    argParser
      ..addFlag(
        'fix',
        abbr: 'f',
        help: 'Fix issues where possible.',
        negatable: false,
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enable verbose output.',
        negatable: false,
      );
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Show information about the installed tooling.';

  @override
  Future<int> run() async {
    final verbose = results['verbose'] == true;
    final shouldFix = results['fix'] == true;
    final flutterVersion = await _tryGetFlutterVersion();
    final output = StringBuffer();
    final shorebirdFlutterPrefix = StringBuffer('Flutter');
    if (flutterVersion != null) {
      shorebirdFlutterPrefix.write(' $flutterVersion');
    }
    output.writeln(
      '''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
$shorebirdFlutterPrefix • revision ${shorebirdEnv.flutterRevision}
Engine • revision ${shorebirdEnv.shorebirdEngineRevision}''',
    );

    if (verbose) {
      const notDetected = 'not detected';
      output.writeln('''

Android Toolchain
  • Android Studio: ${androidStudio.path ?? notDetected}
  • Android SDK: ${androidSdk.path ?? notDetected}
  • ADB: ${androidSdk.adbPath ?? notDetected}
  • JAVA_HOME: ${java.home ?? notDetected}''');
    }

    logger.info(output.toString());

    await doctor.runValidators(doctor.allValidators, applyFixes: shouldFix);

    return ExitCode.success.code;
  }

  Future<String?> _tryGetFlutterVersion() async {
    try {
      return await shorebirdFlutter.getVersion();
    } catch (error) {
      logger.detail('Unable to determine Flutter version.\n$error');
      return null;
    }
  }
}
