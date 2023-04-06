import 'package:shorebird_cli/src/shorebird_paths.dart';
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

    if (!ShorebirdPaths.flutterDirectory.existsSync()) {
      final message =
          'No Flutter directory found at ${ShorebirdPaths.flutterDirectory}';
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
          message: '${ShorebirdPaths.flutterDirectory} has local modifications',
        ),
      );
    }

    if (!await _flutterDirectoryTracksStable()) {
      final message =
          '${ShorebirdPaths.flutterDirectory} is not on the "stable" branch';
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
      final message = 'Shorebird Flutter and the Flutter on your path are '
          'different versions '
          '($shorebirdFlutterVersion vs $pathFlutterVersion)';

      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: message,
        ),
      );
    }

    return issues;
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
      resolveExecutables: !checkPathFlutter,
    );
    final output = result.stdout.toString();

    final match = _flutterVersionRegex.firstMatch(output);
    if (match == null) {
      throw Exception('Could not find version match in $output');
    }

    return match.group(1)!;
  }
}
