import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// {@template init_command}
///
/// `shorebird init`
/// Initialize Shorebird.
/// {@endtemplate}
class InitCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro init_command}
  InitCommand({required super.logger, super.buildUuid});

  @override
  String get description => 'Initialize Shorebird.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    final progress = logger.progress('Initializing Shorebird');

    try {
      if (!hasPubspecYaml) {
        logger.err('Could not find a "pubspec.yaml".');
        return ExitCode.noInput.code;
      }
    } catch (error) {
      logger.err('Error parsing "pubspec.yaml": $error');
      return ExitCode.software.code;
    }

    progress.update('Creating "shorebird.yaml"');

    try {
      if (hasShorebirdYaml) {
        progress.update('"shorebird.yaml" already exists.');
      } else {
        _addShorebirdYamlToProject();
        progress.update('Generated a "shorebird.yaml".');
      }
    } catch (error) {
      progress.fail();
      logger.err('Error creating "shorebird.yaml".\n$error');
      return ExitCode.software.code;
    }

    progress.update('Adding "shorebird.yaml" to "pubspec.yaml" assets');

    if (pubspecContainsShorebirdYaml) {
      progress.update('"shorebird.yaml" already in "pubspec.yaml" assets.');
    } else {
      _addShorebirdYamlToPubspecAssets();
    }

    progress.complete('Initialized Shorebird');

    logger.info(
      '''

${lightGreen.wrap('🐦 Shorebird initialized successfully!')}

✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.

Reference the following commands to get started:

🚙 To run your project use: "${lightCyan.wrap('shorebird run')}".
📦 To build your project use: "${lightCyan.wrap('shorebird build')}".
🚀 To publish a new update use: "${lightCyan.wrap('shorebird publish')}".

For more information, visit ${link(uri: Uri.parse('https://shorebird.dev'))}''',
    );
    return ExitCode.success.code;
  }

  ShorebirdYaml _addShorebirdYamlToProject() {
    final productId = buildUuid();
    File(
      p.join(Directory.current.path, 'shorebird.yaml'),
    ).writeAsStringSync('''
# This file is used to configure the Shorebird CLI.
# Learn more at https://shorebird.dev

# This is the unique identifier for your app.
product_id: $productId
''');

    return ShorebirdYaml(productId: productId);
  }

  void _addShorebirdYamlToPubspecAssets() {
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
}
