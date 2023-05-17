import 'dart:convert';
import 'dart:io';

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
    http.Client? httpClient,
    Uri? hostedUri,
  })  : _httpClient = httpClient ?? http.Client(),
        hostedUri = hostedUri ?? Uri.https('api.shorebird.dev');

  /// The default error message to use when an unknown error occurs.
  static const unknownErrorMessage = 'An unknown error occurred.';

  final http.Client _httpClient;

  /// The hosted uri for the Shorebird CodePush API.
  final Uri hostedUri;

  Uri get _apiV1 => Uri.parse('$hostedUri/api/v1');

  /// Add a new collaborator to the app.
  /// Collaborators can manage the app including its releases and patches.
  Future<void> createAppCollaborator({
    required String appId,
    required int userId,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_apiV1/apps/$appId/collaborators'),
      body: json.encode(CreateAppCollaboratorRequest(userId: userId).toJson()),
    );

    if (response.statusCode != HttpStatus.created) {
      throw _parseErrorResponse(response.body);
    }
  }

  /// Fetches the currently logged-in user.
  Future<User?> getCurrentUser() async {
    final uri = Uri.parse('$_apiV1/users/me');
    final response = await _httpClient.get(uri);

    if (response.statusCode == HttpStatus.notFound) {
      return null;
    } else if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(json);
  }

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
      Uri.parse('$_apiV1/patches/$patchId/artifacts'),
    );
    final file = await http.MultipartFile.fromPath('file', artifactPath);
    request.files.add(file);
    request.fields.addAll({
      'arch': arch,
      'platform': platform,
      'hash': hash,
      'size': '${file.length}',
    });
    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode != HttpStatus.ok) throw _parseErrorResponse(body);

    return PatchArtifact.fromJson(json.decode(body) as Map<String, dynamic>);
  }

  /// Generates a Stripe payment link for the current user.
  Future<Uri> createPaymentLink() async {
    final response = await _httpClient.post(
      Uri.parse('$_apiV1/subscriptions/payment_link'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    return CreatePaymentLinkResponse.fromJson(
      json.decode(response.body) as Json,
    ).paymentLink;
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
      Uri.parse('$_apiV1/releases/$releaseId/artifacts'),
    );
    final file = await http.MultipartFile.fromPath('file', artifactPath);
    request.files.add(file);
    request.fields.addAll({
      'arch': arch,
      'platform': platform,
      'hash': hash,
      'size': '${file.length}',
    });
    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode != HttpStatus.ok) throw _parseErrorResponse(body);

    return ReleaseArtifact.fromJson(json.decode(body) as Map<String, dynamic>);
  }

  /// Create a new app with the provided [displayName].
  /// Returns the newly created app.
  Future<App> createApp({required String displayName}) async {
    final response = await _httpClient.post(
      Uri.parse('$_apiV1/apps'),
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
      Uri.parse('$_apiV1/channels'),
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
      Uri.parse('$_apiV1/patches'),
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
    required String flutterRevision,
    String? displayName,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_apiV1/releases'),
      body: json.encode({
        'app_id': appId,
        'version': version,
        'flutter_revision': flutterRevision,
        if (displayName != null) 'display_name': displayName,
      }),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    return Release.fromJson(body);
  }

  /// Remove [userId] as a collaborator from [appId].
  Future<void> deleteAppCollaborator({
    required String appId,
    required int userId,
  }) async {
    final response = await _httpClient.delete(
      Uri.parse('$_apiV1/apps/$appId/collaborators/$userId'),
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw _parseErrorResponse(response.body);
    }
  }

  /// Delete the release with the provided [releaseId].
  Future<void> deleteRelease({required int releaseId}) async {
    final response = await _httpClient.delete(
      Uri.parse('$_apiV1/releases/$releaseId'),
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw _parseErrorResponse(response.body);
    }
  }

  /// Create a new Shorebird user with the provided [name].
  ///
  /// The email associated with the user's JWT will be used as the user's email.
  Future<User> createUser({
    required String name,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_apiV1/users'),
      body: jsonEncode(CreateUserRequest(name: name).toJson()),
    );

    if (response.statusCode != HttpStatus.created) {
      throw _parseErrorResponse(response.body);
    }

    final body = json.decode(response.body) as Json;
    return User.fromJson(body);
  }

  /// Delete the app with the provided [appId].
  Future<void> deleteApp({required String appId}) async {
    final response = await _httpClient.delete(
      Uri.parse('$_apiV1/apps/$appId'),
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw _parseErrorResponse(response.body);
    }
  }

  /// List all apps for the current account.
  Future<List<AppMetadata>> getApps() async {
    final response = await _httpClient.get(Uri.parse('$_apiV1/apps'));

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
      Uri.parse('$_apiV1/channels').replace(
        queryParameters: {'appId': appId},
      ),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final channels = json.decode(response.body) as List;
    return channels
        .map((channel) => Channel.fromJson(channel as Map<String, dynamic>))
        .toList();
  }

  /// List all collaborators for the provided [appId].
  Future<List<Collaborator>> getCollaborators({required String appId}) async {
    final response = await _httpClient.get(
      Uri.parse('$_apiV1/apps/$appId/collaborators'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final releases = json.decode(response.body) as List;
    return releases
        .map(
            (release) => Collaborator.fromJson(release as Map<String, dynamic>))
        .toList();
  }

  /// List all release for the provided [appId].
  Future<List<Release>> getReleases({required String appId}) async {
    final response = await _httpClient.get(
      Uri.parse('$_apiV1/releases').replace(
        queryParameters: {'appId': appId},
      ),
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
      Uri.parse('$_apiV1/releases/$releaseId/artifacts').replace(
        queryParameters: {
          'arch': arch,
          'platform': platform,
        },
      ),
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
      Uri.parse('$_apiV1/patches/promote'),
      body: json.encode({'patch_id': patchId, 'channel_id': channelId}),
    );

    if (response.statusCode != HttpStatus.created) {
      throw _parseErrorResponse(response.body);
    }
  }

  /// Cancels the current user's subscription.
  Future<DateTime> cancelSubscription() async {
    final response = await _httpClient.delete(
      Uri.parse('$_apiV1/subscriptions'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final timestamp = json['expiration_date'] as int;
    return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
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
