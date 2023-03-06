import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// {@template shorebird_code_push_api_client}
/// The Shorebird CodePush API Client
/// {@endtemplate}
class ShorebirdCodePushApiClient {
  /// {@macro shorebird_code_push_api_client}
  ShorebirdCodePushApiClient({
    required String apiKey,
    http.Client? httpClient,
    Uri? hostedUri,
  })  : _apiKey = apiKey,
        _httpClient = httpClient ?? http.Client(),
        _hostedUri = hostedUri ??
            Uri.https('shorebird-code-push-api-cypqazu4da-uc.a.run.app');

  final String _apiKey;
  final http.Client _httpClient;
  final Uri _hostedUri;

  Map<String, String> get _apiKeyHeader => {'x-api-key': _apiKey};

  /// Upload the artifact at [path] to the
  /// Shorebird CodePush API as a new release.
  Future<void> createRelease(String path) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_hostedUri/api/v1/releases'),
    );
    final file = await http.MultipartFile.fromPath('file', path);
    request.files.add(file);
    request.headers.addAll(_apiKeyHeader);
    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.created) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Download the specified revision of the shorebird engine.
  Future<Uint8List> downloadEngine(String revision) async {
    final request = http.Request(
      'GET',
      Uri.parse('$_hostedUri/api/v1/engines/$revision'),
    );
    request.headers.addAll(_apiKeyHeader);

    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }

    return response.stream.toBytes();
  }
}
