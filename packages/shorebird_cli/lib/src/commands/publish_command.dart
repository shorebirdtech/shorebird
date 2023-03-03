import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_code_push_api_client/shorebird_code_push_api_client.dart';

/// {@template publish_command}
///
/// `shorebird publish <path/to/artifact>`
/// Publish new releases to the Shorebird CodePush server.
/// {@endtemplate}
class PublishCommand extends Command<int> {
  /// {@macro publish_command}
  PublishCommand({
    required Logger logger,
    ShorebirdCodePushApiClient? codePushApiClient,
  })  : _logger = logger,
        _codePushApiClient = codePushApiClient ?? ShorebirdCodePushApiClient();

  @override
  String get description => 'Publish an update.';

  @override
  String get name => 'publish';

  final Logger _logger;
  final ShorebirdCodePushApiClient _codePushApiClient;

  @override
  Future<int> run() async {
    final args = argResults!.rest;
    if (args.isEmpty || args.length > 1) {
      usageException('A single file path must be specified.');
    }

    final artifact = File(args.first);
    if (!artifact.existsSync()) {
      _logger.err('File not found: ${artifact.path}');
      return ExitCode.noInput.code;
    }

    try {
      await _codePushApiClient.createRelease(artifact.path);
    } catch (error) {
      _logger.err('Failed to deploy: $error');
      return ExitCode.software.code;
    }

    _logger.success('Deployed ${artifact.path}!');
    return ExitCode.success.code;
  }
}
