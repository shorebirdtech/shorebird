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
        // Execute a single ping.
        if (platform.isWindows) ...['/n', '1'] else ...['-c', '1'],
        'storage.googleapis.com',
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
