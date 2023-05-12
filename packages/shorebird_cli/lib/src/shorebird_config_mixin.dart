import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

mixin ShorebirdConfigMixin on ShorebirdCommand {
  bool get hasShorebirdYaml => getShorebirdYamlFile().existsSync();

  bool get hasPubspecYaml => getPubspecYaml() != null;

  bool get isShorebirdInitialized {
    return hasShorebirdYaml && pubspecContainsShorebirdYaml;
  }

  Uri? get hostedUri {
    try {
      final baseUrl = getShorebirdYaml()?.baseUrl;
      return baseUrl == null ? null : Uri.tryParse(baseUrl);
    } catch (_) {
      return null;
    }
  }

  bool get pubspecContainsShorebirdYaml {
    final file = File(p.join(Directory.current.path, 'pubspec.yaml'));
    final pubspecContents = file.readAsStringSync();
    final yaml = loadYaml(pubspecContents, sourceUrl: file.uri) as Map;
    if (!yaml.containsKey('flutter')) return false;
    if (!(yaml['flutter'] as Map).containsKey('assets')) return false;
    final assets = (yaml['flutter'] as Map)['assets'] as List;
    return assets.contains('shorebird.yaml');
  }

  File getShorebirdYamlFile() {
    return File(p.join(Directory.current.path, 'shorebird.yaml'));
  }

  ShorebirdYaml? getShorebirdYaml() {
    final file = getShorebirdYamlFile();
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return checkedYamlDecode(yaml, (m) => ShorebirdYaml.fromJson(m!));
  }

  Pubspec? getPubspecYaml() {
    final file = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return Pubspec.parse(yaml);
  }

  ShorebirdYaml addShorebirdYamlToProject(
    String appId, {
    Map<String, String>? flavors,
  }) {
    const content = '''
# This file is used to configure the Shorebird updater used by your application.
# Learn more at https://shorebird.dev
# This file should be checked into version control.

# This is the unique identifier assigned to your app.
# It is used by your app to request the correct patches from Shorebird servers.
app_id:
''';

    final editor = YamlEditor(content)..update(['app_id'], appId);

    if (flavors != null) editor.update(['flavors'], flavors);

    getShorebirdYamlFile().writeAsStringSync(editor.toString());

    return ShorebirdYaml(appId: appId);
  }

  void addShorebirdYamlToPubspecAssets() {
    final pubspecFile = File(p.join(Directory.current.path, 'pubspec.yaml'));
    final pubspecContents = pubspecFile.readAsStringSync();
    final yaml = loadYaml(pubspecContents, sourceUrl: pubspecFile.uri) as Map;
    final editor = YamlEditor(pubspecContents);

    if (!yaml.containsKey('flutter')) {
      editor.update(
        ['flutter'],
        {
          'assets': ['shorebird.yaml']
        },
      );
    } else {
      if (!(yaml['flutter'] as Map).containsKey('assets')) {
        editor.update(['flutter', 'assets'], ['shorebird.yaml']);
      } else {
        final assets = (yaml['flutter'] as Map)['assets'] as List;
        if (!assets.contains('shorebird.yaml')) {
          editor.update(['flutter', 'assets'], [...assets, 'shorebird.yaml']);
        }
      }
    }

    if (editor.edits.isEmpty) return;

    pubspecFile.writeAsStringSync(editor.toString());
  }

  Future<String> getShorebirdFlutterRevision() async {
    final result = await process.run(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: ShorebirdEnvironment.flutterDirectory.path,
    );
    if (result.exitCode != 0) {
      throw Exception('Unable to determine flutter revision: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }
}
