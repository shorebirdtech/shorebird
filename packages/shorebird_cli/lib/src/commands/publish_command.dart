import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template publish_command}
///
/// `shorebird publish <path/to/artifact>`
/// Publish new releases to the Shorebird CodePush server.
/// {@endtemplate}
class PublishCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro publish_command}
  PublishCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
  });

  @override
  String get description => 'Publish an update.';

  @override
  String get name => 'publish';

  @override
  Future<int> run() async {
    if (!isShorebirdInitialized) {
      logger.err(
        'Shorebird is not initialized. Did you run "shorebird init"?',
      );
      return ExitCode.config.code;
    }

    final session = auth.currentSession;
    if (session == null) {
      logger.err('You must be logged in to publish.');
      return ExitCode.noUser.code;
    }

    final args = results.rest;
    if (args.length > 1) {
      usageException('A single file path must be specified.');
    }

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
      final pubspecYaml = getPubspecYaml()!;
      final shorebirdYaml = getShorebirdYaml()!;
      final codePushClient = buildCodePushClient(
        apiKey: session.apiKey,
        hostedUri: hostedUri,
      );
      logger.detail(
        '''Deploying ${artifact.path} to ${shorebirdYaml.appId} (${pubspecYaml.version})''',
      );
      final version = pubspecYaml.version!;
      await codePushClient.createPatch(
        artifactPath: artifact.path,
        releaseVersion: '${version.major}.${version.minor}.${version.patch}',
        appId: shorebirdYaml.appId,
        channel: 'stable',
      );
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.success('Successfully deployed.');
    return ExitCode.success.code;
  }
}
