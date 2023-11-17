import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

class StorageAccessValidator extends Validator {
  @override
  String get description => 'Has access to storage.googleapis.com';

  @override
  Future<List<ValidationIssue>> validate() async {
    final result = await process.run(
      'ping',
      [
        // ping on Windows auto-terminates, but will go on indefinitely on
        // other linux and mac unless we set a count. 2 was chosen arbitrarily.
        if (!platform.isWindows) ...['-c', '2'],
        'https://storage.googleapis.com',
      ],
    );
    if (result.exitCode != ExitCode.success.code) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Unable to access storage.googleapis.com',
        ),
      ];
    }
    return [];
  }
}
