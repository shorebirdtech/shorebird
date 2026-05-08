import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
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

/// A thin [http.BaseClient] decorator that injects the given headers on
/// every outgoing request. Forwards everything else to the wrapped client.
class _HeaderInjectingClient extends http.BaseClient {
  _HeaderInjectingClient({
    required http.Client inner,
    required Map<String, String> headers,
  }) : _inner = inner,
       _headers = headers;

  final http.Client _inner;
  final Map<String, String> _headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Routes requests by their URL host. Requests whose host is in
/// [hostsThroughPrimary] are forwarded to [primaryClient]. All other
/// requests are forwarded to [passthroughClient].
///
/// Used to direct API calls through a failover-aware client while letting
/// requests aimed at unrelated hosts (signed GCS upload URLs, third-party
/// assets, etc.) bypass that machinery and go straight out.
class _HostRouter extends http.BaseClient {
  _HostRouter({
    required http.Client primaryClient,
    required http.Client passthroughClient,
    required this.hostsThroughPrimary,
  }) : _primaryClient = primaryClient,
       _passthroughClient = passthroughClient;

  final http.Client _primaryClient;
  final http.Client _passthroughClient;
  final Set<String> hostsThroughPrimary;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return hostsThroughPrimary.contains(request.url.host)
        ? _primaryClient.send(request)
        : _passthroughClient.send(request);
  }

  /// Closes only [_primaryClient]. Callers are expected to share the
  /// underlying transport with [_passthroughClient] (which transitively
  /// gets closed via the primary), or to manage the passthrough's
  /// lifetime themselves.
  @override
  void close() {
    _primaryClient.close();
    super.close();
  }
}

/// A [http.BaseClient] decorator that adds primary/fallback failover.
///
/// Holds a [_preferredHost] (initially [primaryHost]) and an
/// [_alternateHost] (initially [fallbackHost]). Each request is sent to
/// [_preferredHost]. On a transport-level failure the request is retried
/// once against [_alternateHost], and if that succeeds the two are swapped
/// so the working host becomes preferred for subsequent calls. A session
/// that fell over to the fallback can self-heal back to the primary if
/// the fallback later fails and the primary has recovered.
///
/// This client does not decide which requests are eligible for failover.
/// Pair with [_HostRouter] to send only the appropriate requests through
/// it.
class _FailoverClient extends http.BaseClient {
  _FailoverClient({
    required http.Client inner,
    required this.primaryHost,
    required this.fallbackHost,
  }) : _inner = inner,
       _preferredHost = primaryHost,
       _alternateHost = fallbackHost;

  final http.Client _inner;

  /// The host of the primary API endpoint, e.g. `api.shorebird.dev`.
  final String primaryHost;

  /// The host of the fallback API endpoint, e.g. `api.shorebird.cloud`.
  final String fallbackHost;

  /// The host the next request will be sent to. Updated only when a
  /// failover succeeds, so steady-state requests pay no per-call overhead
  /// for the host decision.
  String _preferredHost;

  /// The host that requests fall over to when [_preferredHost] fails at
  /// the transport layer.
  String _alternateHost;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Capture the host pair locally so this request keeps using the same
    // routing even if a concurrent in-flight request swaps the fields.
    final preferredAtStart = _preferredHost;
    final alternateAtStart = _alternateHost;

    try {
      return await _inner.send(_routedTo(request, preferredAtStart));
    } on Exception catch (e) {
      if (!_isTransportFailure(e)) rethrow;
    }

    final response = await _inner.send(_routedTo(request, alternateAtStart));
    // Swap only if no concurrent send already did. The check and swap are
    // atomic in Dart's single-isolate model because there is no `await`
    // between them.
    if (identical(_preferredHost, preferredAtStart)) {
      _swapHosts();
    }
    return response;
  }

  void _swapHosts() {
    final previousPreferred = _preferredHost;
    _preferredHost = _alternateHost;
    _alternateHost = previousPreferred;
  }

  http.BaseRequest _routedTo(http.BaseRequest original, String host) {
    if (original.url.host == host) return original;
    return _rewriteHost(original, host);
  }

  static bool _isTransportFailure(Exception e) =>
      e is SocketException ||
      e is HandshakeException ||
      e is TimeoutException ||
      e is http.ClientException;

  /// Returns a copy of [original] with its host swapped to [newHost].
  ///
  /// Only supports request types we actually send to API hosts:
  /// [http.Request] for JSON calls, and [http.MultipartRequest] for
  /// field-only metadata POSTs (e.g. createPatchArtifact, which uses
  /// multipart as a form-data envelope and carries no files). Real file
  /// uploads target signed GCS URLs and do not reach this path because
  /// [_HostRouter] sends them straight through.
  static http.BaseRequest _rewriteHost(
    http.BaseRequest original,
    String newHost,
  ) {
    final newUri = original.url.replace(host: newHost);
    if (original is http.Request) {
      return http.Request(original.method, newUri)
        ..headers.addAll(original.headers)
        ..bodyBytes = original.bodyBytes
        ..encoding = original.encoding
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection;
    }
    if (original is http.MultipartRequest) {
      return http.MultipartRequest(original.method, newUri)
        ..headers.addAll(original.headers)
        ..fields.addAll(original.fields)
        ..files.addAll(original.files)
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection;
    }
    // Defensive guard. Unreachable through CodePushClient's public API
    // because every request issued internally is either an http.Request
    // or an http.MultipartRequest. Marked ignore so the unreachable
    // branch does not block the 100% patch coverage check.
    // coverage:ignore-start
    throw StateError(
      'Cannot rewrite host on request of type ${original.runtimeType}',
    );
    // coverage:ignore-end
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// {@template code_push_client}
/// Dart client for the Shorebird CodePush API.
/// {@endtemplate}
class CodePushClient {
  /// {@macro code_push_client}
  factory CodePushClient({
    http.Client? httpClient,
    Uri? hostedUri,
    Uri? fallbackHostedUri,
    Map<String, String>? customHeaders,
  }) {
    final resolvedHosted = hostedUri ?? defaultHostedUri;
    final resolvedFallback = fallbackHostedUri ?? defaultFallbackHostedUri;
    final transport = httpClient ?? buildDefaultHttpClient();
    final apiClient = resolvedHosted.host == resolvedFallback.host
        ? transport
        : _FailoverClient(
            inner: transport,
            primaryHost: resolvedHosted.host,
            fallbackHost: resolvedFallback.host,
          );
    final router = _HostRouter(
      primaryClient: apiClient,
      passthroughClient: transport,
      hostsThroughPrimary: {resolvedHosted.host, resolvedFallback.host},
    );
    final wrapped = _HeaderInjectingClient(
      inner: router,
      headers: {...standardHeaders, ...?customHeaders},
    );
    return CodePushClient._(
      httpClient: wrapped,
      hostedUri: resolvedHosted,
      fallbackHostedUri: resolvedFallback,
    );
  }

  CodePushClient._({
    required http.Client httpClient,
    required this.hostedUri,
    required this.fallbackHostedUri,
  }) : _httpClient = httpClient;

  /// The default primary URI for the Shorebird CodePush API.
  static final Uri defaultHostedUri = Uri.https('api.shorebird.dev');

  /// The default fallback URI used when the primary is unreachable.
  static final Uri defaultFallbackHostedUri = Uri.https('api.shorebird.cloud');

  /// How long to wait for a TCP/TLS handshake before treating the endpoint
  /// as unreachable and falling back. Applies only to connection setup, not
  /// to response time. Healthy handshakes complete in well under a second.
  static const defaultConnectionTimeout = Duration(seconds: 3);

  /// Builds the default [http.Client] used when no client is supplied. The
  /// client is configured with [defaultConnectionTimeout] so that an
  /// unreachable primary surfaces as a transport-level error rather than
  /// hanging.
  static http.Client buildDefaultHttpClient({
    Duration connectionTimeout = defaultConnectionTimeout,
  }) {
    final inner = HttpClient()..connectionTimeout = connectionTimeout;
    return IOClient(inner);
  }

  /// The standard headers applied to all requests.
  static const standardHeaders = <String, String>{'x-version': packageVersion};

  /// The default error message to use when an unknown error occurs.
  static const unknownErrorMessage = 'An unknown error occurred.';

  final http.Client _httpClient;

  /// The hosted uri for the Shorebird CodePush API.
  final Uri hostedUri;

  /// The fallback hosted uri used when [hostedUri] is unreachable at the
  /// transport layer. Defaults to `https://api.shorebird.cloud`.
  final Uri fallbackHostedUri;

  Uri get _v1 => Uri.parse('$hostedUri/api/v1');

  /// Fetches the currently logged-in user.
  Future<PrivateUser?> getCurrentUser() async {
    final uri = Uri.parse('$_v1/users/me');
    final response = await _httpClient.get(uri);

    if (response.statusCode == HttpStatus.notFound) {
      return null;
    } else if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PrivateUser.fromJson(json);
  }

  /// Create a new artifact for a specific [patchId].
  Future<void> createPatchArtifact({
    required String artifactPath,
    required String appId,
    required int patchId,
    required String arch,
    required ReleasePlatform platform,
    required String hash,
    String? hashSignature,
    String? podfileLockHash,
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
      'hash_signature': ?hashSignature,
      'podfile_lock_hash': ?podfileLockHash,
    });
    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, body);
    }

    final decoded = CreatePatchArtifactResponse.fromJson(
      json.decode(body) as Map<String, dynamic>,
    );

    final uploadRequest = http.MultipartRequest('POST', Uri.parse(decoded.url))
      ..files.add(file);

    final uploadResponse = await _httpClient.send(uploadRequest);

    if (!uploadResponse.isSuccess) {
      throw CodePushException(
        message:
            '''Failed to upload artifact (${uploadResponse.reasonPhrase} '${uploadResponse.statusCode})''',
      );
    }
  }

  /// Create a new artifact for a specific [releaseId].
  Future<void> createReleaseArtifact({
    required String artifactPath,
    required String appId,
    required int releaseId,
    required String arch,
    required ReleasePlatform platform,
    required String hash,
    required bool canSideload,
    required String? podfileLockHash,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_v1/apps/$appId/releases/$releaseId/artifacts'),
    );
    final file = await http.MultipartFile.fromPath('file', artifactPath);

    // `toJson` returns proper JSON types; multipart fields are always
    // strings on the wire. Drop null-valued keys so absent-optional
    // fields don't send the literal string "null" (previously handled
    // by `@JsonKey(includeIfNull: false)` in the handwritten model).
    final payload = <String, String>{
      for (final entry in CreateReleaseArtifactRequest(
        arch: arch,
        platform: platform,
        hash: hash,
        size: file.length,
        canSideload: canSideload,
        filename: p.basename(artifactPath),
        podfileLockHash: podfileLockHash,
      ).toJson().entries)
        if (entry.value != null) entry.key: '${entry.value}',
    };
    request.fields.addAll(payload);

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, body);
    }

    final decoded = CreateReleaseArtifactResponse.fromJson(
      json.decode(body) as Map<String, dynamic>,
    );

    final uploadRequest = http.MultipartRequest('POST', Uri.parse(decoded.url))
      ..files.add(file);

    final uploadResponse = await _httpClient.send(uploadRequest);

    if (!uploadResponse.isSuccess) {
      throw CodePushException(
        message:
            '''Failed to upload artifact (${uploadResponse.reasonPhrase} '${uploadResponse.statusCode})''',
      );
    }
  }

  /// Create a new app with the provided [displayName].
  /// Returns the newly created app.
  Future<App> createApp({
    required int organizationId,
    required String displayName,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/apps'),
      body: json.encode(
        CreateAppRequest(
          organizationId: organizationId,
          displayName: displayName,
        ).toJson(),
      ),
    );

    if (!response.isSuccess) {
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

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    return Channel.fromJson(body);
  }

  /// Create a new patch for the given [releaseId].
  Future<Patch> createPatch({
    required String appId,
    required int releaseId,
    required Json metadata,
  }) async {
    final request = CreatePatchRequest(
      releaseId: releaseId,
      metadata: metadata,
    );
    final response = await _httpClient.post(
      Uri.parse('$_v1/apps/$appId/patches'),
      body: json.encode(request.toJson()),
    );

    if (!response.isSuccess) {
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
    String? flutterVersion,
    String? displayName,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/apps/$appId/releases'),
      body: json.encode({
        'version': version,
        'flutter_revision': flutterRevision,
        'flutter_version': ?flutterVersion,
        'display_name': ?displayName,
      }),
    );

    if (!response.isSuccess) {
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
    Json? metadata,
  }) async {
    final response = await _httpClient.patch(
      Uri.parse('$_v1/apps/$appId/releases/$releaseId'),
      body: json.encode(
        UpdateReleaseRequest(
          status: status,
          platform: platform,
          metadata: metadata,
        ).toJson(),
      ),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Create a new Shorebird user with the provided [name].
  ///
  /// The email associated with the user's JWT will be used as the user's email.
  Future<PrivateUser> createUser({required String name}) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/users'),
      body: jsonEncode(CreateUserRequest(name: name).toJson()),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final body = json.decode(response.body) as Json;
    return PrivateUser.fromJson(body);
  }

  /// Delete the app with the provided [appId].
  Future<void> deleteApp({required String appId}) async {
    final response = await _httpClient.delete(Uri.parse('$_v1/apps/$appId'));

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// List all apps for the current account.
  Future<List<AppMetadata>> getApps() async {
    final response = await _httpClient.get(Uri.parse('$_v1/apps'));

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final decoded = GetAppsResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    return decoded.apps;
  }

  /// List all channels for the provided [appId].
  Future<List<Channel>> getChannels({required String appId}) async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/apps/$appId/channels'),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final channels = json.decode(response.body) as List;
    return channels
        .map((channel) => Channel.fromJson(channel as Map<String, dynamic>))
        .toList();
  }

  /// List all release for the provided [appId].
  Future<List<Release>> getReleases({
    required String appId,
    bool sideloadableOnly = false,
  }) async {
    var uri = Uri.parse('$_v1/apps/$appId/releases');
    if (sideloadableOnly) {
      uri = uri.replace(queryParameters: {'sideloadable': 'true'});
    }

    final response = await _httpClient.get(uri);

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final decoded = GetReleasesResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    return decoded.releases;
  }

  /// Gets [ReleasePatch]es associated with [appId]'s [releaseId].
  Future<List<ReleasePatch>> getPatches({
    required String appId,
    required int releaseId,
  }) async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/apps/$appId/releases/$releaseId/patches'),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    return GetReleasePatchesResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    ).patches;
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
          'arch': ?arch,
          if (platform != null) 'platform': platform.name,
        },
      ),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final decoded = GetReleaseArtifactsResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    return decoded.artifacts;
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

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Gets the list of organizations the user is a member of, along with the
  /// user's role in each organization.
  Future<List<OrganizationMembership>> getOrganizationMemberships() async {
    final response = await _httpClient.get(Uri.parse('$_v1/organizations'));

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    return GetOrganizationsResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    ).organizations;
  }

  /// Returns a GCP upload link for measuring upload speed.
  Future<Uri> getGCPUploadSpeedTestUrl() async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/diagnostics/gcp_upload'),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final jsonBody = json.decode(response.body) as Map<String, dynamic>;
    return Uri.parse(jsonBody['upload_url'] as String);
  }

  /// Returns a GCP download link for measuring download speed.
  Future<Uri> getGCPDownloadSpeedTestUrl() async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/diagnostics/gcp_download'),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final jsonBody = json.decode(response.body) as Map<String, dynamic>;
    return Uri.parse(jsonBody['download_url'] as String);
  }

  /// Closes the client.
  void close() => _httpClient.close();

  CodePushException _parseErrorResponse(int statusCode, String response) {
    // No idea why, but Dart 3.3.0 claims this line is not covered by tests.
    // coverage:ignore-start
    final exceptionBuilder = switch (statusCode) {
      // coverage:ignore-end
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
    } on Exception {
      throw exceptionBuilder(message: unknownErrorMessage);
    }
    return exceptionBuilder(message: error.message, details: error.details);
  }
}

extension on http.BaseResponse {
  /// Whether the response has a 2xx status code.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}
