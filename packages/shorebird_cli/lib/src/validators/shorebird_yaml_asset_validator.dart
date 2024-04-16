import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/commands/init_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:yaml/yaml.dart';

/// Verifies that the shorebird.yaml is found in pubspec.yaml assets.
class ShorebirdYamlAssetValidator extends Validator {
  final String pubspecYamlPath = 'pubspec.yaml';

  @override
  String get description => 'shorebird.yaml found in pubspec.yaml assets';

  @override
  bool canRunInCurrentContext() => _pubspecYamlFile?.existsSync() ?? false;

  @override
  String get incorrectContextMessage => '''
The pubspec.yaml file does not exist.
The command you are running must be run within a Flutter app project.''';

  @override
  Future<List<ValidationIssue>> validate() async {
    final pubspecYamlFile = _pubspecYamlFile;
    if (!canRunInCurrentContext()) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'No pubspec.yaml file found',
        ),
      ];
    }

    if (pubspecYamlFile != null) {
      final pubspecContent = pubspecYamlFile.readAsStringSync();
      final pubspecYaml = loadYaml(pubspecContent) as YamlMap;

      if (!_pubspecYamlHasShorebirdAsset(pubspecYaml)) {
        return [
          ValidationIssue(
            severity: ValidationIssueSeverity.error,
            message: 'No shorebird.yaml found in pubspec.yaml assets',
            fix: () =>
                InitCommand.addShorebirdYamlToPubspecAssets(pubspecYamlFile),
          ),
        ];
      }
    }

    return [];
  }

  File? get _pubspecYamlFile {
    final root = shorebirdEnv.getFlutterProjectRoot();
    if (root == null) return null;
    return File(p.join(root.path, 'pubspec.yaml'));
  }

  bool _pubspecYamlHasShorebirdAsset(YamlMap pubspecYaml) {
    if (!pubspecYaml.containsKey('flutter')) {
      return false;
    }

    final flutterSection = pubspecYaml['flutter'];
    if (flutterSection is YamlMap) {
      if (!flutterSection.containsKey('assets')) {
        return false;
      }
      final assetsSection = flutterSection['assets'];
      if (assetsSection is YamlList) {
        return assetsSection.any((asset) => asset == 'shorebird.yaml');
      }
    }
    return false;
  }
}
