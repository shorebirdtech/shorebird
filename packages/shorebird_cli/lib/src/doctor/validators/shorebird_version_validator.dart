import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/commands/doctor_command.dart';
import 'package:shorebird_cli/src/doctor/doctor_validator.dart';

/// Verifies that the currently installed version of Shorebird is the latest.
class ShorebirdVersionValidator extends DoctorValidator {
  ShorebirdVersionValidator({required this.doctorCommand});

  final DoctorCommand doctorCommand;

  @override
  String get description => 'Shorebird is up-to-date';

  @override
  Future<List<ValidationIssue>> validate() async {
    final workingDirectory = p.dirname(Platform.script.toFilePath());
    final isShorebirdUpToDate = await doctorCommand.isShorebirdVersionCurrent(
      workingDirectory: workingDirectory,
    );

    if (!isShorebirdUpToDate) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: '''
A new version of shorebird is available!
Run `shorebird upgrade` to upgrade.
''',
        )
      ];
    }

    return [];
  }
}
