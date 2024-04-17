import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Verifies that the shorebird.yaml is found in pubspec.yaml assets.
class ShorebirdYamlAssetValidator extends Validator {
  @override
  String get description => 'shorebird.yaml found in pubspec.yaml assets';

  @override
  bool canRunInCurrentContext() => shorebirdEnv.hasPubspecYaml;

  @override
  String get incorrectContextMessage => '''
The pubspec.yaml file does not exist.
The command you are running must be run within a Flutter app project.''';

  @override
  Future<List<ValidationIssue>> validate() async {
    if (!canRunInCurrentContext()) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'No pubspec.yaml file found',
        ),
      ];
    }

    if (shorebirdEnv.pubspecContainsShorebirdYaml) {
      return [];
    }

    final root = shorebirdEnv.getFlutterProjectRoot();
    if (root != null) {
      final pubspecYamlFile = shorebirdEnv.getPubspecYamlFile(cwd: root);
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'No shorebird.yaml found in pubspec.yaml assets',
          fix: () =>
              ShorebirdEnv.addShorebirdYamlToPubspecAssets(pubspecYamlFile),
        ),
      ];
    }

    return [];
  }
}
