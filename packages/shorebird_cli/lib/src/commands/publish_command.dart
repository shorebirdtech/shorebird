import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command_runner.dart';

/// {@template publish_command}
///
/// `shorebird publish <path/to/artifact>`
/// Publish new releases to the Shorebird CodePush server.
/// {@endtemplate}
class PublishCommand extends Command<int> {
  /// {@macro publish_command}
  PublishCommand({
    required Logger logger,
    required Auth auth,
    required ShorebirdCodePushApiClientBuilder codePushApiClientBuilder,
  })  : _auth = auth,
        _buildCodePushApiClient = codePushApiClientBuilder,
        _logger = logger;

  @override
  String get description => 'Publish an update.';

  @override
  String get name => 'publish';

  final Auth _auth;
  final ShorebirdCodePushApiClientBuilder _buildCodePushApiClient;
  final Logger _logger;

  @override
  Future<int> run() async {
    final session = _auth.currentSession;
    if (session == null) {
      _logger.err('You must be logged in to publish.');
      return ExitCode.noUser.code;
    }

    final args = argResults!.rest;
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
      _logger.err('File not found: ${artifact.path}');
      return ExitCode.noInput.code;
    }

    try {
      final codePushApiClient = _buildCodePushApiClient(
        apiKey: session.apiKey,
      );
      await codePushApiClient.createRelease(artifact.path);
    } catch (error) {
      _logger.err('Failed to deploy: $error');
      return ExitCode.software.code;
    }

    _logger.success('Deployed ${artifact.path}!');
    return ExitCode.success.code;
  }
}
