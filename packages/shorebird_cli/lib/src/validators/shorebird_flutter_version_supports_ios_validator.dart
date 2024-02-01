import 'package:mason_logger/mason_logger.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

class ShorebirdFlutterVersionSupportsIOSValidator extends Validator {
  ShorebirdFlutterVersionSupportsIOSValidator();

  @override
  String get description => 'Shorebird Flutter version supports iOS';

  @override
  Future<List<ValidationIssue>> validate() async {
    final issues = <ValidationIssue>[];

    // TODO(eseidel): Share "parse version" logic with the
    // ShorebirdFlutterValidator.
    final flutterVersion = await shorebirdFlutter.getVersion();
    if (flutterVersion == null) {
      issues.add(
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Failed to determine Shorebird Flutter version',
        ),
      );
      return issues;
    }

    // Our new mixed-mode engine had crashes in our last release of 3.16.4
    // through several releases of 3.16.7.  There are OK release of 3.16.7
    // but it's easier to just warn away from all of 3.16.7.
    // We did not release 3.16.8 so we're recommending 3.16.9.
    final firstBadFlutter = Version(3, 16, 4);
    final lastBadFlutter = Version(3, 16, 7);
    final recommendedFlutter = Version(3, 16, 9);
    final useFlutterVersionCommand = lightCyan.wrap(
      'shorebird flutter versions use $recommendedFlutter',
    );
    // This is a warning to encourage those patching older versions of Flutter
    // to upgrade.
    if (flutterVersion < firstBadFlutter) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: '''
Shorebird iOS recommends Flutter $recommendedFlutter or later.
Run $useFlutterVersionCommand to upgrade.
''',
        ),
      );
    }
    // This is an error to disallow known-bad versions of Flutter for iOS.
    if (flutterVersion >= firstBadFlutter && flutterVersion <= lastBadFlutter) {
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: '''
Shorebird iOS does not support Flutter $flutterVersion.
Run $useFlutterVersionCommand to upgrade.
''',
        ),
      );
    }

    return issues;
  }
}
