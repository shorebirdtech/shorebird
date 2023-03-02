import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';

/// {@template sample_command}
///
/// `shorebird sample`
/// A [Command] to exemplify a sub command
/// {@endtemplate}
class PublishCommand extends Command<int> {
  /// {@macro sample_command}
  PublishCommand({required Logger logger, http.Client? httpClient})
      : _logger = logger,
        _httpClient = httpClient ?? http.Client();

  @override
  String get description => 'Publish an update.';

  @override
  String get name => 'publish';

  final Logger _logger;
  final http.Client _httpClient;

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

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://localhost:8080/api/v1/releases'),
    );
    final file = await http.MultipartFile.fromPath('file', artifact.path);
    request.files.add(file);
    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.created) {
      _logger.err(
        'Failed to deploy: ${response.statusCode} ${response.reasonPhrase}',
      );
      return ExitCode.software.code;
    }

    _logger.success('Deployed ${artifact.path}!');

    return ExitCode.success.code;
  }
}
