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
        _hostedUri =
            hostedUri ?? Uri.https('code-push-server-kmdbqkx7rq-uc.a.run.app');

  final String _apiKey;
  final http.Client _httpClient;
  final Uri _hostedUri;

  Map<String, String> get _apiKeyHeader => {'x-api-key': _apiKey};

  /// Create a new patch.
  Future<void> createPatch({
    required String baseVersion,
    required String productId,
    required String channel,
    required String artifactPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_hostedUri/api/v1/patches'),
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
}
