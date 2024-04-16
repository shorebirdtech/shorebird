import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

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
            fix: () => _addShorebirdAssetToFile(pubspecYamlFile),
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

  void _addShorebirdAssetToFile(File pubspecYamlFile) {
    final pubspecContent = pubspecYamlFile.readAsStringSync();
    final yamlEditor = YamlEditor(pubspecContent);
    final emptyYamlNode = wrapAsYamlNode(null);
    final flutterNode =
        yamlEditor.parseAt(['flutter'], orElse: () => emptyYamlNode);
    if (flutterNode == emptyYamlNode) {
      yamlEditor.update(
        ['flutter'],
        wrapAsYamlNode({
          'assets': ['shorebird.yaml'],
        }),
      );
    } else {
      final assetsNode = yamlEditor
          .parseAt(['flutter', 'assets'], orElse: () => emptyYamlNode);
      if (assetsNode == emptyYamlNode) {
        if (flutterNode is YamlMap) {
          yamlEditor.update(['flutter', 'assets'], ['shorebird.yaml']);
        } else {
          yamlEditor.update(
            ['flutter'],
            wrapAsYamlNode({
              'assets': ['shorebird.yaml'],
            }),
          );
        }
      } else {
        final assetsList = assetsNode.value;
        if (assetsList is YamlList) {
          if (!assetsList.contains('shorebird.yaml')) {
            final newAssetsList = [...assetsList, 'shorebird.yaml'];
            yamlEditor.update(['flutter', 'assets'], newAssetsList);
          }
        } else {
          yamlEditor.update(['flutter', 'assets'], ['shorebird.yaml']);
        }
      }
    }

    pubspecYamlFile.writeAsStringSync(yamlEditor.toString());
  }
}
