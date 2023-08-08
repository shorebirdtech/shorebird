import 'dart:io';

import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Verifies that the currently installed version of Shorebird is the latest.
class ShorebirdVersionValidator extends Validator {
  ShorebirdVersionValidator();

  @override
  String get description => 'Shorebird is up-to-date';

  @override
  bool canRunInCurrentContext() => true;

  @override
  Future<List<ValidationIssue>> validate() async {
    final bool isShorebirdUpToDate;

    try {
      isShorebirdUpToDate = await shorebirdVersion.isLatest();
    } on ProcessException catch (e) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Failed to get shorebird version. Error: ${e.message}',
        ),
      ];
    }

    if (!isShorebirdUpToDate) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: '''
A new version of shorebird is available! Run `shorebird upgrade` to upgrade.''',
        )
      ];
    }

    return [];
  }
}
