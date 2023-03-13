import 'dart:convert';
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
        hostedUri =
            hostedUri ?? Uri.https('code-push-server-kmdbqkx7rq-uc.a.run.app');

  final String _apiKey;
  final http.Client _httpClient;

  /// The hosted uri for the Shorebird CodePush API.
  final Uri hostedUri;

  Map<String, String> get _apiKeyHeader => {'x-api-key': _apiKey};

  /// Create a new app with the provided [productId].
  Future<void> createApp({required String productId}) async {
    final response = await _httpClient.post(
      Uri.parse('$hostedUri/api/v1/apps'),
      headers: _apiKeyHeader,
      body: json.encode({'product_id': productId}),
    );

    if (response.statusCode != HttpStatus.created) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Create a new patch.
  Future<void> createPatch({
    required String baseVersion,
    required String productId,
    required String channel,
    required String artifactPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$hostedUri/api/v1/patches'),
    );
    final file = await http.MultipartFile.fromPath('file', artifactPath);
    request.files.add(file);
    request.fields.addAll({
      'base_version': baseVersion,
      'product_id': productId,
      'channel': channel,
    });
    request.headers.addAll(_apiKeyHeader);
    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.created) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Delete the app with the provided [productId].
  Future<void> deleteApp({required String productId}) async {
    final response = await _httpClient.delete(
      Uri.parse('$hostedUri/api/v1/apps/$productId'),
      headers: _apiKeyHeader,
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Download the specified revision of the shorebird engine.
  Future<Uint8List> downloadEngine(String revision) async {
    final request = http.Request(
      'GET',
      Uri.parse(
        // TODO(felangel): use the revision instead of hardcoded "dev".
        'https://storage.googleapis.com/code-push-dev.appspot.com/engines/dev/engine.zip',
      ),
    );
    request.headers.addAll(_apiKeyHeader);

    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }

    return response.stream.toBytes();
  }

  /// Closes the client.
  void close() => _httpClient.close();
}
