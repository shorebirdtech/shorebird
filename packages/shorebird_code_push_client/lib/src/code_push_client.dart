import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template code_push_exception}
/// Base class for all CodePush exceptions.
/// {@endtemplate}
class CodePushException implements Exception {
  /// {@macro code_push_exception}
  const CodePushException({required this.message, this.details});

  /// The message associated with the exception.
  final String message;

  /// The details associated with the exception.
  final String? details;

  @override
  String toString() => '$message${details != null ? '\n$details' : ''}';
}

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
        hostedUri = hostedUri ?? Uri.https('api.shorebird.dev');

  /// The default error message to use when an unknown error occurs.
  static const unknownErrorMessage = 'An unknown error occurred.';

  final String _apiKey;
  final http.Client _httpClient;

  /// The hosted uri for the Shorebird CodePush API.
  final Uri hostedUri;

  Map<String, String> get _apiKeyHeader => {'x-api-key': _apiKey};

  /// Create a new artifact for a specific [patchId].
  Future<PatchArtifact> createPatchArtifact({
    required String artifactPath,
    required int patchId,
    required String arch,
    required String platform,
    required String hash,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$hostedUri/api/v1/patches/$patchId/artifacts'),
    );
    final file = await http.MultipartFile.fromPath('file', artifactPath);
    request.files.add(file);
    request.fields.addAll({
      'arch': arch,
      'platform': platform,
      'hash': hash,
      'size': '${file.length}',
    });
    request.headers.addAll(_apiKeyHeader);
    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode != HttpStatus.ok) throw _parseErrorResponse(body);

    return PatchArtifact.fromJson(json.decode(body) as Map<String, dynamic>);
  }

  /// Create a new artifact for a specific [releaseId].
  Future<ReleaseArtifact> createReleaseArtifact({
    required String artifactPath,
    required int releaseId,
    required String arch,
    required String platform,
    required String hash,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$hostedUri/api/v1/releases/$releaseId/artifacts'),
    );
    final file = await http.MultipartFile.fromPath('file', artifactPath);
    request.files.add(file);
    request.fields.addAll({
      'arch': arch,
      'platform': platform,
      'hash': hash,
      'size': '${file.length}',
    });
    request.headers.addAll(_apiKeyHeader);
    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode != HttpStatus.ok) throw _parseErrorResponse(body);

    return ReleaseArtifact.fromJson(json.decode(body) as Map<String, dynamic>);
  }

  /// Create a new app with the provided [displayName].
  /// Returns the newly created app.
  Future<App> createApp({required String displayName}) async {
    final response = await _httpClient.post(
      Uri.parse('$hostedUri/api/v1/apps'),
      headers: _apiKeyHeader,
      body: json.encode({'display_name': displayName}),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    return App.fromJson(body);
  }

  /// Create a new channel for the app with the provided [appId].
  Future<Channel> createChannel({
    required String appId,
    required String channel,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$hostedUri/api/v1/channels'),
      headers: _apiKeyHeader,
      body: json.encode({'app_id': appId, 'channel': channel}),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    return Channel.fromJson(body);
  }

  /// Create a new patch for the given [releaseId].
  Future<Patch> createPatch({required int releaseId}) async {
    final response = await _httpClient.post(
      Uri.parse('$hostedUri/api/v1/patches'),
      headers: _apiKeyHeader,
      body: json.encode({'release_id': releaseId}),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    return Patch.fromJson(body);
  }

  /// Create a new release for the app with the provided [appId].
  Future<Release> createRelease({
    required String appId,
    required String version,
    String? displayName,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$hostedUri/api/v1/releases'),
      headers: _apiKeyHeader,
      body: json.encode({
        'app_id': appId,
        'version': version,
        if (displayName != null) 'display_name': displayName,
      }),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    return Release.fromJson(body);
  }

  /// Delete the app with the provided [appId].
  Future<void> deleteApp({required String appId}) async {
    final response = await _httpClient.delete(
      Uri.parse('$hostedUri/api/v1/apps/$appId'),
      headers: _apiKeyHeader,
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw _parseErrorResponse(response.body);
    }
  }

  /// Download the specified revision of the shorebird engine.
  Future<Uint8List> downloadEngine({required String revision}) async {
    final request = http.Request(
      'GET',
      Uri.parse('$hostedUri/api/v1/engines/$revision'),
    );
    request.headers.addAll(_apiKeyHeader);

    final response = await _httpClient.send(request);

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('${response.statusCode} ${response.reasonPhrase}');
    }

    return response.stream.toBytes();
  }

  /// List all apps for the current account.
  Future<List<AppMetadata>> getApps() async {
    final response = await _httpClient.get(
      Uri.parse('$hostedUri/api/v1/apps'),
      headers: _apiKeyHeader,
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final apps = json.decode(response.body) as List;
    return apps
        .map((app) => AppMetadata.fromJson(app as Map<String, dynamic>))
        .toList();
  }

  /// List all channels for the provided [appId].
  Future<List<Channel>> getChannels({required String appId}) async {
    final response = await _httpClient.get(
      Uri.parse('$hostedUri/api/v1/channels').replace(
        queryParameters: {'appId': appId},
      ),
      headers: _apiKeyHeader,
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final channels = json.decode(response.body) as List;
    return channels
        .map((channel) => Channel.fromJson(channel as Map<String, dynamic>))
        .toList();
  }

  /// List all release for the provided [appId].
  Future<List<Release>> getReleases({required String appId}) async {
    final response = await _httpClient.get(
      Uri.parse('$hostedUri/api/v1/releases').replace(
        queryParameters: {'appId': appId},
      ),
      headers: _apiKeyHeader,
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final releases = json.decode(response.body) as List;
    return releases
        .map((release) => Release.fromJson(release as Map<String, dynamic>))
        .toList();
  }

  /// Get a release artifact for a specific [releaseId], [arch], and [platform].
  Future<ReleaseArtifact> getReleaseArtifact({
    required int releaseId,
    required String arch,
    required String platform,
  }) async {
    final response = await _httpClient.get(
      Uri.parse('$hostedUri/api/v1/releases/$releaseId/artifacts').replace(
        queryParameters: {
          'arch': arch,
          'platform': platform,
        },
      ),
      headers: _apiKeyHeader,
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    return ReleaseArtifact.fromJson(body);
  }

  /// Promote the [patchId] to the [channelId].
  Future<void> promotePatch({
    required int patchId,
    required int channelId,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$hostedUri/api/v1/patches/promote'),
      headers: _apiKeyHeader,
      body: json.encode({'patch_id': patchId, 'channel_id': channelId}),
    );

    if (response.statusCode != HttpStatus.created) {
      throw _parseErrorResponse(response.body);
    }
  }

  /// Closes the client.
  void close() => _httpClient.close();

  CodePushException _parseErrorResponse(String response) {
    final ErrorResponse error;
    try {
      final body = json.decode(response) as Map<String, dynamic>;
      error = ErrorResponse.fromJson(body);
    } catch (_) {
      throw const CodePushException(message: unknownErrorMessage);
    }
    return CodePushException(message: error.message, details: error.details);
  }
}
