import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

class FlutterValidationException implements Exception {
  const FlutterValidationException(this.message);

  /// The message associated with the exception.
  final String message;

  @override
  String toString() => 'FlutterValidationException: $message';
}

class ShorebirdFlutterValidator extends Validator {
  ShorebirdFlutterValidator();

  final _flutterVersionRegex = RegExp(r'Flutter (\d+.\d+.\d+)');

  // coverage:ignore-start
  @override
  String get description => 'Flutter install is correct';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate(ShorebirdProcess process) async {
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

    if (!await _flutterDirectoryIsClean(process)) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: '${ShorebirdEnvironment.flutterDirectory} has local '
              'modifications',
        ),
      );
    }

    if (!await _flutterDirectoryTracksCorrectRevision(process)) {
      final message =
          '''${ShorebirdEnvironment.flutterDirectory} is not on the correct revision''';
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: message,
        ),
      );
    }

    String? shorebirdFlutterVersion;
    try {
      shorebirdFlutterVersion = await _shorebirdFlutterVersion(process);
    } catch (error) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Failed to determine Shorebird Flutter version. $error',
        ),
      );
    }

    String? pathFlutterVersion;
    try {
      pathFlutterVersion = await _pathFlutterVersion(process);
    } catch (error) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Failed to determine path Flutter version. $error',
        ),
      );
    }

    if (shorebirdFlutterVersion != null &&
        pathFlutterVersion != null &&
        shorebirdFlutterVersion != pathFlutterVersion) {
      final message = '''
The version of Flutter that Shorebird includes and the Flutter on your path are different.
\tShorebird Flutter: $shorebirdFlutterVersion
\tSystem Flutter:    $pathFlutterVersion
This can cause unexpected behavior if you are switching between the tools and the version gap is wide. If you have any trouble, please let us know on Shorebird discord.''';

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

  Future<bool> _flutterDirectoryIsClean(ShorebirdProcess process) async {
    final result = await process.run(
      'git',
      ['status'],
      workingDirectory: ShorebirdEnvironment.flutterDirectory.path,
    );
    return result.stdout
        .toString()
        .contains('nothing to commit, working tree clean');
  }

  Future<bool> _flutterDirectoryTracksCorrectRevision(
    ShorebirdProcess process,
  ) async {
    final result = await process.run(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: ShorebirdEnvironment.flutterDirectory.path,
    );
    return result.stdout
        .toString()
        .contains(ShorebirdEnvironment.flutterRevision);
  }

  Future<String> _shorebirdFlutterVersion(ShorebirdProcess process) =>
      _getFlutterVersion(
        process: process,
        checkPathFlutter: false,
      );

  Future<String> _pathFlutterVersion(ShorebirdProcess process) =>
      _getFlutterVersion(
        process: process,
        checkPathFlutter: true,
      );

  Future<String> _getFlutterVersion({
    required ShorebirdProcess process,
    required bool checkPathFlutter,
  }) async {
    final result = await process.run(
      'flutter',
      ['--version'],
      useVendedFlutter: !checkPathFlutter,
    );

    if (result.exitCode != 0) {
      throw FlutterValidationException(
        'Flutter version check did not complete successfully. ${result.stderr}',
      );
    }

    final output = result.stdout.toString();
    final match = _flutterVersionRegex.firstMatch(output);
    if (match == null) {
      throw FlutterValidationException(
        'Could not find version number in $output',
      );
    }

    return match.group(1)!;
  }
}
