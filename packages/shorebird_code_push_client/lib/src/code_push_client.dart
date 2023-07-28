import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';
import 'package:shorebird_code_push_client/src/version.dart';
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

/// {@template code_push_forbidden_exception}
/// Exception thrown when a 403 response is received.
/// {@endtemplate}
class CodePushForbiddenException extends CodePushException {
  /// {@macro code_push_forbidden_exception}
  CodePushForbiddenException({required super.message, super.details});
}

/// {@template code_push_conflict_exception}
/// Exception thrown when a 409 response is received.
/// {@endtemplate}
class CodePushConflictException extends CodePushException {
  /// {@macro code_push_conflict_exception}
  const CodePushConflictException({required super.message, super.details});
}

/// {@template code_push_not_found_exception}
/// Exception thrown when a 404 response is received.
/// {@endtemplate}
class CodePushNotFoundException extends CodePushException {
  /// {@macro code_push_not_found_exception}
  CodePushNotFoundException({required super.message, super.details});
}

/// {@template code_push_upgrade_required_exception}
/// Exception thrown when a 426 response is received.
/// {@endtemplate}
class CodePushUpgradeRequiredException extends CodePushException {
  /// {@macro code_push_upgrade_required_exception}
  const CodePushUpgradeRequiredException({
    required super.message,
    super.details,
  });
}

/// A wrapper around [http.Client] that ensures all outbound requests
/// are consistent.
/// For example, all requests include the standard `x-version` header.
class _CodePushHttpClient extends http.BaseClient {
  _CodePushHttpClient(this._client);

  final http.Client _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return retry(
      () => _client.send(request..headers.addAll(CodePushClient.headers)),
      retryIf: (e) => e is! CodePushException,
    );
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

/// {@template code_push_client}
/// Dart client for the Shorebird CodePush API.
/// {@endtemplate}
class CodePushClient {
  /// {@macro code_push_client}
  CodePushClient({
    http.Client? httpClient,
    Uri? hostedUri,
  })  : _httpClient = _CodePushHttpClient(httpClient ?? http.Client()),
        hostedUri = hostedUri ?? Uri.https('api.shorebird.dev');

  /// The standard headers applied to all requests.
  static const headers = <String, String>{'x-version': packageVersion};

  /// The default error message to use when an unknown error occurs.
  static const unknownErrorMessage = 'An unknown error occurred.';

  final http.Client _httpClient;

  /// The hosted uri for the Shorebird CodePush API.
  final Uri hostedUri;

  Uri get _v1 => Uri.parse('$hostedUri/api/v1');

  /// Add a new collaborator to the app.
  /// Collaborators can manage the app including its releases and patches.
  Future<void> createCollaborator({
    required String appId,
    required String email,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/apps/$appId/collaborators'),
      body: json.encode(CreateAppCollaboratorRequest(email: email).toJson()),
    );

    if (response.statusCode != HttpStatus.created) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Fetches the currently logged-in user.
  Future<User?> getCurrentUser() async {
    final uri = Uri.parse('$_v1/users/me');
    final response = await _httpClient.get(uri);

    if (response.statusCode == HttpStatus.notFound) {
      return null;
    } else if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(json);
  }

  /// Create a new artifact for a specific [patchId].
  Future<void> createPatchArtifact({
    required String artifactPath,
    required String appId,
    required int patchId,
    required String arch,
    required ReleasePlatform platform,
    required String hash,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_v1/apps/$appId/patches/$patchId/artifacts'),
    );
    final file = await http.MultipartFile.fromPath('file', artifactPath);
    request.fields.addAll({
      'arch': arch,
      'platform': platform.name,
      'hash': hash,
      'size': '${file.length}',
    });
    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, body);
    }

    final decoded = CreatePatchArtifactResponse.fromJson(
      json.decode(body) as Map<String, dynamic>,
    );

    final uploadResponse = await _httpClient.put(
      Uri.parse(decoded.url),
      body: File(artifactPath).readAsBytesSync(),
    );
    if (uploadResponse.statusCode != HttpStatus.ok) {
      throw CodePushException(
        message:
            '''Failed to upload artifact (${uploadResponse.reasonPhrase} '${uploadResponse.statusCode})''',
      );
    }
  }

  /// Generates a Stripe payment link for the current user.
  Future<Uri> createPaymentLink() async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/subscriptions/payment_link'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    return CreatePaymentLinkResponse.fromJson(
      json.decode(response.body) as Json,
    ).paymentLink;
  }

  /// Create a new artifact for a specific [releaseId].
  Future<void> createReleaseArtifact({
    required String artifactPath,
    required String appId,
    required int releaseId,
    required String arch,
    required ReleasePlatform platform,
    required String hash,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_v1/apps/$appId/releases/$releaseId/artifacts'),
    );
    final file = await http.MultipartFile.fromPath('file', artifactPath);
    request.fields.addAll({
      'arch': arch,
      'platform': platform.name,
      'hash': hash,
      'size': '${file.length}',
    });
    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, body);
    }

    final decoded = CreateReleaseArtifactResponse.fromJson(
      json.decode(body) as Map<String, dynamic>,
    );

    final uploadResponse = await _httpClient.put(
      Uri.parse(decoded.url),
      body: File(artifactPath).readAsBytesSync(),
    );
    if (uploadResponse.statusCode != HttpStatus.ok) {
      throw CodePushException(
        message:
            '''Failed to upload artifact (${uploadResponse.reasonPhrase} '${uploadResponse.statusCode})''',
      );
    }
  }

  /// Create a new app with the provided [displayName].
  /// Returns the newly created app.
  Future<App> createApp({required String displayName}) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/apps'),
      body: json.encode({'display_name': displayName}),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
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
      Uri.parse('$_v1/apps/$appId/channels'),
      body: json.encode({'channel': channel}),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    return Channel.fromJson(body);
  }

  /// Create a new patch for the given [releaseId].
  Future<Patch> createPatch({
    required String appId,
    required int releaseId,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/apps/$appId/patches'),
      body: json.encode({'release_id': releaseId}),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
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
      Uri.parse('$_v1/apps/$appId/releases'),
      body: json.encode({
        'version': version,
        'flutter_revision': flutterRevision,
        if (displayName != null) 'display_name': displayName,
      }),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final createReleaseResponse = CreateReleaseResponse.fromJson(body);
    return createReleaseResponse.release;
  }

  /// Updates the specified release's status to [status].
  Future<void> updateReleaseStatus({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required ReleaseStatus status,
  }) async {
    final response = await _httpClient.patch(
      Uri.parse('$_v1/apps/$appId/releases/$releaseId'),
      body: json.encode(
        UpdateReleaseRequest(
          status: status,
          platform: platform,
        ).toJson(),
      ),
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Remove [userId] as a collaborator from [appId].
  Future<void> deleteCollaborator({
    required String appId,
    required int userId,
  }) async {
    final response = await _httpClient.delete(
      Uri.parse('$_v1/apps/$appId/collaborators/$userId'),
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Delete the release with the provided [releaseId].
  Future<void> deleteRelease({
    required String appId,
    required int releaseId,
  }) async {
    final response = await _httpClient.delete(
      Uri.parse('$_v1/apps/$appId/releases/$releaseId'),
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Create a new Shorebird user with the provided [name].
  ///
  /// The email associated with the user's JWT will be used as the user's email.
  Future<User> createUser({
    required String name,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/users'),
      body: jsonEncode(CreateUserRequest(name: name).toJson()),
    );

    if (response.statusCode != HttpStatus.created) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final body = json.decode(response.body) as Json;
    return User.fromJson(body);
  }

  /// Delete the app with the provided [appId].
  Future<void> deleteApp({required String appId}) async {
    final response = await _httpClient.delete(
      Uri.parse('$_v1/apps/$appId'),
    );

    if (response.statusCode != HttpStatus.noContent) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// List all apps for the current account.
  Future<List<AppMetadata>> getApps() async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/apps'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final apps = json.decode(response.body) as List;
    return apps
        .map((app) => AppMetadata.fromJson(app as Map<String, dynamic>))
        .toList();
  }

  /// List all channels for the provided [appId].
  Future<List<Channel>> getChannels({required String appId}) async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/apps/$appId/channels'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final channels = json.decode(response.body) as List;
    return channels
        .map((channel) => Channel.fromJson(channel as Map<String, dynamic>))
        .toList();
  }

  /// List all collaborators for the provided [appId].
  Future<List<Collaborator>> getCollaborators({required String appId}) async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/apps/$appId/collaborators'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final collaborators = json.decode(response.body) as List;
    return collaborators
        .map(
          (collaborator) => Collaborator.fromJson(
            collaborator as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  /// List all release for the provided [appId].
  Future<List<Release>> getReleases({required String appId}) async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/apps/$appId/releases'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final releases = json.decode(response.body) as List;
    return releases
        .map((release) => Release.fromJson(release as Map<String, dynamic>))
        .toList();
  }

  /// Get all release artifacts for a specific [releaseId]
  /// and optional [arch] and [platform].
  Future<List<ReleaseArtifact>> getReleaseArtifacts({
    required String appId,
    required int releaseId,
    String? arch,
    ReleasePlatform? platform,
  }) async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/apps/$appId/releases/$releaseId/artifacts').replace(
        queryParameters: {
          if (arch != null) 'arch': arch,
          if (platform != null) 'platform': platform.name,
        },
      ),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final decoded = GetReleaseArtifactsResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    return decoded.artifacts;
  }

  /// Get all usage information for the associated account.
  Future<GetUsageResponse> getUsage() async {
    final response = await _httpClient.get(Uri.parse('$_v1/usage'));

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    return GetUsageResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  /// Promote the [patchId] to the [channelId].
  Future<void> promotePatch({
    required String appId,
    required int patchId,
    required int channelId,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/apps/$appId/patches/promote'),
      body: json.encode({'patch_id': patchId, 'channel_id': channelId}),
    );

    if (response.statusCode != HttpStatus.created) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Cancels the current user's subscription.
  Future<DateTime> cancelSubscription() async {
    final response = await _httpClient.delete(Uri.parse('$_v1/subscriptions'));

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final timestamp = json['expiration_date'] as int;
    return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  }

  /// Closes the client.
  void close() => _httpClient.close();

  CodePushException _parseErrorResponse(int statusCode, String response) {
    final exceptionBuilder = switch (statusCode) {
      HttpStatus.conflict => CodePushConflictException.new,
      HttpStatus.notFound => CodePushNotFoundException.new,
      HttpStatus.upgradeRequired => CodePushUpgradeRequiredException.new,
      HttpStatus.forbidden => CodePushForbiddenException.new,
      _ => CodePushException.new,
    };

    final ErrorResponse error;
    try {
      final body = json.decode(response) as Map<String, dynamic>;
      error = ErrorResponse.fromJson(body);
    } catch (_) {
      throw exceptionBuilder(message: unknownErrorMessage);
    }
    return exceptionBuilder(message: error.message, details: error.details);
  }
}
