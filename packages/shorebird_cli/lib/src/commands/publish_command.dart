import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// {@template publish_command}
///
/// `shorebird publish <path/to/artifact>`
/// Publish new releases to the Shorebird CodePush server.
/// {@endtemplate}
class PublishCommand extends ShorebirdCommand {
  /// {@macro publish_command}
  PublishCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.buildUuid,
  });

  @override
  String get description => 'Publish an update.';

  @override
  String get name => 'publish';

  @override
  Future<int> run() async {
    final session = auth.currentSession;
    if (session == null) {
      logger.err('You must be logged in to publish.');
      return ExitCode.noUser.code;
    }

    final args = results.rest;
    if (args.length > 1) {
      usageException('A single file path must be specified.');
    }

    late final Pubspec? pubspecYaml;
    try {
      pubspecYaml = _readPubspecYaml();
      if (pubspecYaml == null) {
        logger.err('Could not find a "pubspec.yaml".');
        return ExitCode.noInput.code;
      }
    } catch (error) {
      logger.err('Error parsing "pubspec.yaml": $error');
      return ExitCode.software.code;
    }

    late final String productId;
    late final ShorebirdYaml? shorebirdYaml;
    try {
      shorebirdYaml = _readShorebirdYaml();
    } catch (error) {
      logger.err('Error parsing "shorebird.yaml": $error');
      return ExitCode.software.code;
    }

    if (shorebirdYaml == null) {
      productId = buildUuid();
      File(
        p.join(Directory.current.path, 'shorebird.yaml'),
      ).writeAsStringSync('''
# This file is used to configure the Shorebird CLI.
# Learn more at https://shorebird.dev

# This is the unique identifier for your app.
product_id: $productId
''');
      logger.info('Generated a "shorebird.yaml".');
    } else {
      productId = shorebirdYaml.productId;
    }

    _addShorebirdYamlToAssets();

    final artifactPath = args.isEmpty
        ? p.join(
            Directory.current.path,
            'build',
            'app',
            'intermediates',
            'stripped_native_libs',
            'release',
            'out',
            'lib',
            'arm64-v8a',
            'libapp.so',
          )
        : args.first;

    final artifact = File(artifactPath);
    if (!artifact.existsSync()) {
      logger.err('Artifact not found: "${artifact.path}"');
      return ExitCode.noInput.code;
    }

    try {
      final codePushClient = buildCodePushClient(apiKey: session.apiKey);
      logger.detail(
        'Deploying ${artifact.path} to $productId (${pubspecYaml.version})',
      );
      final version = pubspecYaml.version!;
      await codePushClient.createPatch(
        artifactPath: artifact.path,
        baseVersion: '${version.major}.${version.minor}.${version.patch}',
        productId: productId,
        channel: 'stable',
      );
    } catch (error) {
      logger.err('Failed to deploy: $error');
      return ExitCode.software.code;
    }

    logger.success('Successfully deployed.');
    return ExitCode.success.code;
  }

  ShorebirdYaml? _readShorebirdYaml() {
    final file = File(p.join(Directory.current.path, 'shorebird.yaml'));
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return checkedYamlDecode(yaml, (m) => ShorebirdYaml.fromJson(m!));
  }

  Pubspec? _readPubspecYaml() {
    final file = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return Pubspec.parse(yaml);
  }

  void _addShorebirdYamlToAssets() {
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

    if (editor.edits.isNotEmpty) {
      pubspecFile.writeAsStringSync(editor.toString());
      logger.info('Added "shorebird.yaml" to "pubspec.yaml".');
    }
  }
}
