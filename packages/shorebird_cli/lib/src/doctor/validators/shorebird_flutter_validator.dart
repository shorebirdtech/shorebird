import 'package:shorebird_cli/src/doctor/doctor_validator.dart';
import 'package:shorebird_cli/src/shorebird_paths.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

class ShorebirdFlutterValidator extends DoctorValidator {
  ShorebirdFlutterValidator({required this.runProcess});

  final RunProcess runProcess;

  // coverage:ignore-start
  @override
  String get description => 'Flutter install is correct';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate() async {
    if (!ShorebirdPaths.flutterDirectory.existsSync()) {
      final message =
          'No Flutter directory found at ${ShorebirdPaths.flutterDirectory}';
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: message,
        ),
      ];
    }

    if (!await _flutterDirectoryIsClean()) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: '${ShorebirdPaths.flutterDirectory} has local modifications',
        ),
      ];
    }

    if (!await _flutterDirectoryTracksStable()) {
      final message =
          '${ShorebirdPaths.flutterDirectory} is not on the "stable" branch';
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: message,
        ),
      ];
    }

    return [];
  }

  Future<bool> _flutterDirectoryIsClean() async {
    final result = await runProcess(
      'git',
      ['status'],
      workingDirectory: ShorebirdPaths.flutterDirectory.path,
    );
    return result.stdout
        .toString()
        .contains('nothing to commit, working tree clean');
  }

  Future<bool> _flutterDirectoryTracksStable() async {
    final result = await runProcess(
      'git',
      ['--no-pager', 'branch'],
      workingDirectory: ShorebirdPaths.flutterDirectory.path,
    );
    return result.stdout.toString().contains('* stable');
  }
}
