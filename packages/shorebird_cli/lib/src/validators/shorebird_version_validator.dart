import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/validators/validators.dart';

/// Verifies that the currently installed version of Shorebird is the latest.
class ShorebirdVersionValidator extends DoctorValidator {
  ShorebirdVersionValidator({required this.isShorebirdVersionCurrent});

  final Future<bool> Function({required String workingDirectory})
      isShorebirdVersionCurrent;

  // coverage:ignore-start
  @override
  String get description => 'Shorebird is up-to-date';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate() async {
    final workingDirectory = p.dirname(Platform.script.toFilePath());
    final isShorebirdUpToDate = await isShorebirdVersionCurrent(
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
