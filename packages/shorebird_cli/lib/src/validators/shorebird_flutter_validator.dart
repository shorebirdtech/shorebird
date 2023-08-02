import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:version/version.dart';

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

  @override
  String get description => 'Flutter install is correct';

  @override
  bool canRunInCurrentContext() => true;

  @override
  Future<List<ValidationIssue>> validate() async {
    final issues = <ValidationIssue>[];

    if (!shorebirdEnv.flutterDirectory.existsSync()) {
      final message = 'No Flutter directory found at '
          '${shorebirdEnv.flutterDirectory}';
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
          message: '${shorebirdEnv.flutterDirectory} has local '
              'modifications',
        ),
      );
    }

    String? shorebirdFlutterVersionString;
    try {
      shorebirdFlutterVersionString = await _shorebirdFlutterVersion(process);
    } catch (error) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Failed to determine Shorebird Flutter version. $error',
        ),
      );
    }

    String? pathFlutterVersionString;
    try {
      pathFlutterVersionString = await _pathFlutterVersion(process);
    } catch (error) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Failed to determine path Flutter version. $error',
        ),
      );
    }

    if (shorebirdFlutterVersionString != null &&
        pathFlutterVersionString != null) {
      final shorebirdFlutterVersion =
          Version.parse(shorebirdFlutterVersionString);
      final pathFlutterVersion = Version.parse(pathFlutterVersionString);
      if (shorebirdFlutterVersion.major != pathFlutterVersion.major ||
          shorebirdFlutterVersion.minor != pathFlutterVersion.minor) {
        final message = '''
The version of Flutter that Shorebird includes and the Flutter on your path are different.
\tShorebird Flutter: $shorebirdFlutterVersionString
\tSystem Flutter:    $pathFlutterVersionString
This can cause unexpected behavior if you are switching between the tools and the version gap is wide. If you have any trouble, please let us know on Shorebird discord.''';

        issues.add(
          ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: message,
          ),
        );
      }
    }

    final flutterStorageEnvironmentValue =
        platform.environment['FLUTTER_STORAGE_BASE_URL'];
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
      ['status', '--untracked-files=no', '--porcelain'],
      workingDirectory: shorebirdEnv.flutterDirectory.path,
    );
    return result.stdout.toString().trim().isEmpty;
  }

  Future<String> _shorebirdFlutterVersion(ShorebirdProcess process) {
    return _getFlutterVersion(process: process);
  }

  Future<String> _pathFlutterVersion(ShorebirdProcess process) {
    return _getFlutterVersion(
      process: process,
      useVendedFlutter: false,
    );
  }

  Future<String> _getFlutterVersion({
    required ShorebirdProcess process,
    bool useVendedFlutter = true,
  }) async {
    final result = await process.run(
      'flutter',
      ['--version'],
      useVendedFlutter: useVendedFlutter,
      runInShell: true,
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
