import 'dart:io';

import 'package:http/http.dart' as http;

/// {@template shorebird_code_push_api_client}
/// The Shorebird CodePush API Client
/// {@endtemplate}
class ShorebirdCodePushApiClient {
  /// {@macro shorebird_code_push_api_client}
  ShorebirdCodePushApiClient({http.Client? httpClient, Uri? hostedUri})
      : _httpClient = httpClient ?? http.Client(),
        _hostedUri = hostedUri ??
            Uri.https('shorebird-code-push-api-cypqazu4da-uc.a.run.app');

  final http.Client _httpClient;
  final Uri _hostedUri;

  /// Upload the artifact at [path] to the
  /// Shorebird CodePush API as a new release.
  Future<void> createRelease(String path) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_hostedUri/api/v1/releases'),
    );
    final file = await http.MultipartFile.fromPath('file', path);
    request.files.add(file);
    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.created) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }
  }
}
