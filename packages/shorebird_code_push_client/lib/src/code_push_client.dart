import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template code_push_client}
/// Dart client for the Shorebird CodePush API.
/// {@endtemplate}
class CodePushClient {
  /// {@macro code_push_client}
  CodePushClient({
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

  /// Create a new app with the provided [appId].
  Future<void> createApp({required String appId}) async {
    final response = await _httpClient.post(
      Uri.parse('$hostedUri/api/v1/apps'),
      headers: _apiKeyHeader,
      body: json.encode({'app_id': appId}),
    );

    if (response.statusCode != HttpStatus.created) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Create a new patch.
  Future<void> createPatch({
    required String releaseVersion,
    required String appId,
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
      'release_version': releaseVersion,
      'app_id': appId,
      'channel': channel,
    });
    request.headers.addAll(_apiKeyHeader);
    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.created) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Delete the app with the provided [appId].
  Future<void> deleteApp({required String appId}) async {
    final response = await _httpClient.delete(
      Uri.parse('$hostedUri/api/v1/apps/$appId'),
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

  /// List all apps for the current account.
  Future<List<App>> getApps() async {
    final response = await _httpClient.get(
      Uri.parse('$hostedUri/api/v1/apps'),
      headers: _apiKeyHeader,
    );

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }

    final apps = json.decode(response.body) as List;
    return apps
        .map((app) => App.fromJson(app as Map<String, dynamic>))
        .toList();
  }

  /// Closes the client.
  void close() => _httpClient.close();
}
