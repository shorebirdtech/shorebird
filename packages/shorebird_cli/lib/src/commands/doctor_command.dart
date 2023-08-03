import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/version.dart';

/// {@template doctor_command}
/// `shorebird doctor`
/// A command that checks for potential issues with the current shorebird
/// environment.
/// {@endtemplate}
class DoctorCommand extends ShorebirdCommand {
  /// {@macro doctor_command}
  DoctorCommand() {
    argParser.addFlag(
      'fix',
      abbr: 'f',
      help: 'Fix issues where possible.',
      negatable: false,
    );
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Show information about the installed tooling.';

  @override
  Future<int> run() async {
    final shouldFix = results['fix'] == true;

    logger.info('''

Shorebird v$packageVersion
Shorebird Engine • revision ${shorebirdEnv.shorebirdEngineRevision()}
''');

    await doctor.runValidators(doctor.allValidators, applyFixes: shouldFix);

    return ExitCode.success.code;
  }
}
