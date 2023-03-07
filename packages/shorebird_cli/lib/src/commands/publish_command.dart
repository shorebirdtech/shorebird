import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';

/// {@template publish_command}
///
/// `shorebird publish <path/to/artifact>`
/// Publish new releases to the Shorebird CodePush server.
/// {@endtemplate}
class PublishCommand extends ShorebirdCommand {
  /// {@macro publish_command}
  PublishCommand({super.auth, super.buildCodePushClient, super.logger});

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

    final releasePath = args.isEmpty
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

    final artifact = File(releasePath);
    if (!artifact.existsSync()) {
      logger.err('File not found: ${artifact.path}');
      return ExitCode.noInput.code;
    }

    try {
      final codePushApiClient = buildCodePushClient(apiKey: session.apiKey);
      await codePushApiClient.createRelease(artifact.path);
    } catch (error) {
      logger.err('Failed to deploy: $error');
      return ExitCode.software.code;
    }

    logger.success('Deployed ${artifact.path}!');
    return ExitCode.success.code;
  }
}
