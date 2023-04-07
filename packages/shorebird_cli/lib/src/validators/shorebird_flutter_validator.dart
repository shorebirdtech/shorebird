import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

class ShorebirdFlutterValidator extends Validator {
  ShorebirdFlutterValidator({required this.runProcess});

  final RunProcess runProcess;
  final _flutterVersionRegex = RegExp(r'Flutter (\d+.\d+.\d+)');

  // coverage:ignore-start
  @override
  String get description => 'Flutter install is correct';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate() async {
    final issues = <ValidationIssue>[];

    if (!ShorebirdEnvironment.flutterDirectory.existsSync()) {
      final message = 'No Flutter directory found at '
          '${ShorebirdEnvironment.flutterDirectory}';
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: message,
        ),
      );
    }

    if (!await _flutterDirectoryIsClean()) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: '${ShorebirdEnvironment.flutterDirectory} has local '
              'modifications',
        ),
      );
    }

    if (!await _flutterDirectoryTracksStable()) {
      final message =
          '${ShorebirdEnvironment.flutterDirectory} is not on the "stable" '
          'branch';
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: message,
        ),
      );
    }

    final shorebirdFlutterVersion = await _shorebirdFlutterVersion();
    final pathFlutterVersion = await _pathFlutterVersion();

    if (shorebirdFlutterVersion != pathFlutterVersion) {
      final message = """
Shorebird Flutter and the Flutter on your path are different versions.
\tShorebird Flutter: $shorebirdFlutterVersion
\tSystem Flutter:    $pathFlutterVersion
This can cause unexpected behavior if the version gap is wide. If you're seeing this unexpectedly, please let us know on Shorebird discord!""";

      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: message,
        ),
      );
    }

    final flutterStorageEnvironmentValue =
        ShorebirdEnvironment.environment['FLUTTER_STORAGE_BASE_URL'];
    if (flutterStorageEnvironmentValue != null &&
        flutterStorageEnvironmentValue.isNotEmpty) {
      issues.add(
        const ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: 'Shorebird does not respect the FLUTTER_STORAGE_BASE_URL '
              'environment variable at this time',
        ),
      );
    }

    return issues;
  }

  Future<bool> _flutterDirectoryIsClean() async {
    final result = await runProcess(
      'git',
      ['status'],
      workingDirectory: ShorebirdEnvironment.flutterDirectory.path,
    );
    return result.stdout
        .toString()
        .contains('nothing to commit, working tree clean');
  }

  Future<bool> _flutterDirectoryTracksStable() async {
    final result = await runProcess(
      'git',
      ['--no-pager', 'branch'],
      workingDirectory: ShorebirdEnvironment.flutterDirectory.path,
    );
    return result.stdout.toString().contains('* stable');
  }

  Future<String> _shorebirdFlutterVersion() => _getFlutterVersion(
        checkPathFlutter: false,
      );

  Future<String> _pathFlutterVersion() => _getFlutterVersion(
        checkPathFlutter: true,
      );

  Future<String> _getFlutterVersion({
    required bool checkPathFlutter,
  }) async {
    final result = await runProcess(
      'flutter',
      ['--version'],
      useVendedFlutter: !checkPathFlutter,
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Flutter version check did not complete successfully.'
        '\n${result.stderr}',
      );
    }

    final output = result.stdout.toString();
    final match = _flutterVersionRegex.firstMatch(output);
    if (match == null) {
      throw Exception('Could not find version match in $output');
    }

    return match.group(1)!;
  }
}
