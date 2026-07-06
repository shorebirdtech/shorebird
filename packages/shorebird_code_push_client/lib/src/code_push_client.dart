import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_client/src/version.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template code_push_exception}
/// Base class for all CodePush exceptions.
/// {@endtemplate}
class CodePushException implements Exception {
  /// {@macro code_push_exception}
  const CodePushException({required this.message, this.details, this.code});

  /// The message associated with the exception.
  final String message;

  /// The details associated with the exception.
  final String? details;

  /// The machine-readable error code from the server's error response, if
  /// one was present. Lets callers branch on the specific failure (e.g.
  /// distinguishing the two artifact-conflict cases) without matching on
  /// human-readable text.
  final String? code;

  @override
  String toString() => '$message${details != null ? '\n$details' : ''}';
}

/// {@template code_push_forbidden_exception}
/// Exception thrown when a 403 response is received.
/// {@endtemplate}
class CodePushForbiddenException extends CodePushException {
  /// {@macro code_push_forbidden_exception}
  CodePushForbiddenException({
    required super.message,
    super.details,
    super.code,
  });
}

/// {@template code_push_conflict_exception}
/// Exception thrown when a 409 response is received.
/// {@endtemplate}
class CodePushConflictException extends CodePushException {
  /// {@macro code_push_conflict_exception}
  const CodePushConflictException({
    required super.message,
    super.details,
    super.code,
  });

  /// The server error code for an artifact conflict where the existing
  /// artifact's hash differs from the uploaded one — the existing artifact
  /// was built from different code, so the caller must not treat the upload
  /// as published.
  static const artifactHashMismatchCode =
      'patch_artifacts_create_existing_artifact_hash_mismatch';

  /// The server error code for an artifact conflict where the existing
  /// artifact's hash matches the uploaded one — an honest retry of bytes the
  /// server already has, the only conflict a caller may treat as success.
  static const identicalArtifactAlreadyExistsCode =
      'patch_artifacts_create_existing_artifact';

  /// The server error code for a patch-create whose correlation key resolves
  /// to a patch that has been rolled back. Rolled-back patches are never
  /// served to devices and rollback is permanent, so the key cannot be reused
  /// on that release — publishing under it would ship nothing while looking
  /// like a success.
  static const existingPatchRolledBackCode =
      'patches_create_existing_patch_rolled_back';

  /// Whether this conflict is a different-bytes collision (see
  /// [artifactHashMismatchCode]).
  bool get isArtifactHashMismatch => code == artifactHashMismatchCode;

  /// Whether this conflict is a correlation-key hit on a rolled-back patch
  /// (see [existingPatchRolledBackCode]).
  bool get isExistingPatchRolledBack => code == existingPatchRolledBackCode;

  /// Whether the server explicitly confirmed an identical artifact already
  /// exists (see [identicalArtifactAlreadyExistsCode]). Only this exact code
  /// grants success — a conflict with any other (or no) code, such as a
  /// proxy-generated 409, an unparseable body, or a future server conflict
  /// variant, carries no guarantee that the bytes are published.
  bool get isIdenticalArtifactAlreadyExists =>
      code == identicalArtifactAlreadyExistsCode;
}

/// {@template code_push_not_found_exception}
/// Exception thrown when a 404 response is received.
/// {@endtemplate}
class CodePushNotFoundException extends CodePushException {
  /// {@macro code_push_not_found_exception}
  CodePushNotFoundException({
    required super.message,
    super.details,
    super.code,
  });
}

/// {@template code_push_upgrade_required_exception}
/// Exception thrown when a 426 response is received.
/// {@endtemplate}
class CodePushUpgradeRequiredException extends CodePushException {
  /// {@macro code_push_upgrade_required_exception}
  const CodePushUpgradeRequiredException({
    required super.message,
    super.details,
    super.code,
  });
}

/// A wrapper around [http.Client] that ensures all outbound requests
/// are consistent.
/// For example, all requests include the standard `x-version` header.
class _CodePushHttpClient extends http.BaseClient {
  _CodePushHttpClient(this._client, this._headers);

  final http.Client _client;

  final Map<String, String> _headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
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
    Map<String, String>? customHeaders,
    @visibleForTesting
    Duration uploadRetryBaseDelay = const Duration(seconds: 1),
  }) : _httpClient = _CodePushHttpClient(httpClient ?? http.Client(), {
         ...standardHeaders,
         ...?customHeaders,
       }),
       _uploadRetryBaseDelay = uploadRetryBaseDelay,
       hostedUri = hostedUri ?? Uri.https('api.shorebird.dev');

  /// The standard headers applied to all requests.
  @visibleForTesting
  static const standardHeaders = <String, String>{'x-version': packageVersion};

  /// The default error message to use when an unknown error occurs.
  @visibleForTesting
  static const unknownErrorMessage = 'An unknown error occurred.';

  /// The status GCS returns ("Resume Incomplete") between resumable chunks.
  static const _resumeIncompleteStatus = 308;

  /// The maximum number of consecutive failures tolerated while uploading a
  /// single resumable session before the upload is abandoned.
  static const _maxUploadFailures = 5;

  final http.Client _httpClient;

  /// The base delay for exponential backoff between resumable upload retries.
  /// Doubles with each consecutive failure.
  final Duration _uploadRetryBaseDelay;

  /// The hosted uri for the Shorebird CodePush API.
  final Uri hostedUri;

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

    await _uploadArtifact(
      artifactPath: artifactPath,
      multipartFile: file,
      url: decoded.url,
      uploadMethod: decoded.uploadMethod,
    );
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

    await _uploadArtifact(
      artifactPath: artifactPath,
      multipartFile: file,
      url: decoded.url,
      uploadMethod: decoded.uploadMethod,
    );
  }

  /// Uploads an artifact's bytes to storage using the method the server
  /// selected in the create response.
  Future<void> _uploadArtifact({
    required String artifactPath,
    required http.MultipartFile multipartFile,
    required String url,
    required ArtifactUploadMethod? uploadMethod,
  }) async {
    if (uploadMethod == ArtifactUploadMethod.resumable) {
      await _resumableUpload(
        sessionUri: Uri.parse(url),
        artifactPath: artifactPath,
      );
      return;
    }

    // Legacy single multipart POST. Remove once the server no longer returns
    // ArtifactUploadMethod.multipart (i.e. all supported clients are new
    // enough to receive a resumable session).
    final uploadRequest = http.MultipartRequest('POST', Uri.parse(url))
      ..files.add(multipartFile);
    final uploadResponse = await _httpClient.send(uploadRequest);
    if (!uploadResponse.isSuccess) {
      throw _uploadFailed(uploadResponse);
    }
  }

  /// Uploads [artifactPath] to a GCS resumable session at [sessionUri] by
  /// PUTing the bytes in fixed-size chunks with a `Content-Range` header,
  /// resuming from the last byte GCS acknowledged if a chunk fails. The
  /// session was initiated (and size-bound) server-side.
  Future<void> _resumableUpload({
    required Uri sessionUri,
    required String artifactPath,
  }) async {
    // GCS requires chunk sizes to be a multiple of 256 KiB (except the last).
    const chunkSize = 8 * 1024 * 1024;

    final file = File(artifactPath);
    final total = await file.length();
    final raf = await file.open();
    var failures = 0;
    try {
      var offset = 0;
      while (offset < total) {
        final end = offset + chunkSize < total ? offset + chunkSize : total;
        await raf.setPosition(offset);
        final chunk = await raf.read(end - offset);

        final http.StreamedResponse response;
        try {
          response = await _httpClient.send(
            http.Request('PUT', sessionUri)
              ..bodyBytes = chunk
              ..headers['content-range'] = 'bytes $offset-${end - 1}/$total',
          );
        } on Exception {
          // Network failure mid-chunk: back off, ask GCS how far it got, and
          // resume from there.
          if (++failures > _maxUploadFailures) rethrow;
          await _backoff(failures);
          offset = await _queryResumeOffset(sessionUri, total);
          continue;
        }

        final status = response.statusCode;
        await response.stream.drain<void>();

        if (status == HttpStatus.ok || status == HttpStatus.created) return;

        if (status == _resumeIncompleteStatus) {
          // A 308 reports GCS's stored byte count in the `range` header. Its
          // absence means GCS has no bytes yet, so we must restart from 0
          // (per the resumable upload status-check docs). Treat a lack of
          // forward progress as a failure so a stuck session can't spin
          // forever.
          final next = _parseRangeEnd(response.headers['range']) ?? 0;
          if (next > offset) {
            failures = 0;
          } else if (++failures > _maxUploadFailures) {
            throw _uploadFailed(response);
          } else {
            await _backoff(failures);
          }
          offset = next;
        } else if (status >= HttpStatus.internalServerError) {
          // Transient server error (5xx): recover the same way as a mid-chunk
          // network failure — back off, then resume from where GCS left off
          // rather than re-sending bytes it has already persisted.
          if (++failures > _maxUploadFailures) throw _uploadFailed(response);
          await _backoff(failures);
          offset = await _queryResumeOffset(sessionUri, total);
        } else {
          throw _uploadFailed(response);
        }
      }
    } finally {
      await raf.close();
    }
  }

  /// Waits with exponential backoff before retrying a resumable upload,
  /// doubling [_uploadRetryBaseDelay] with each consecutive [failures].
  Future<void> _backoff(int failures) =>
      Future<void>.delayed(_uploadRetryBaseDelay * (1 << (failures - 1)));

  /// Queries a resumable [sessionUri] for the number of bytes GCS has received
  /// so far, returning the offset to resume from.
  Future<int> _queryResumeOffset(Uri sessionUri, int total) async {
    final response = await _httpClient.send(
      http.Request('PUT', sessionUri)
        ..headers['content-range'] = 'bytes */$total',
    );
    final status = response.statusCode;
    await response.stream.drain<void>();
    if (status == HttpStatus.ok || status == HttpStatus.created) return total;
    if (status == _resumeIncompleteStatus) {
      return _parseRangeEnd(response.headers['range']) ?? 0;
    }
    throw _uploadFailed(response);
  }

  /// Parses the next byte offset from a GCS `Range: bytes=0-X` header,
  /// returning `X + 1`, or null if the header is absent/malformed.
  int? _parseRangeEnd(String? range) {
    if (range == null) return null;
    final dash = range.lastIndexOf('-');
    if (dash == -1) return null;
    final last = int.tryParse(range.substring(dash + 1));
    return last == null ? null : last + 1;
  }

  /// The exception thrown when an artifact upload request fails.
  CodePushException _uploadFailed(http.BaseResponse response) {
    final reason = response.reasonPhrase;
    return CodePushException(
      message: 'Failed to upload artifact ($reason ${response.statusCode})',
    );
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
  ///
  /// When [clientPatchId] is supplied and a patch on this release already
  /// has that id, the server returns the existing patch — letting two
  /// invocations across platforms share one patch number. The returned
  /// [CreatePatchResponse] echoes [clientPatchId] back so callers can
  /// verify the correlation.
  Future<CreatePatchResponse> createPatch({
    required String appId,
    required int releaseId,
    required Json metadata,
    String? clientPatchId,
    String? gitSha,
  }) async {
    // Coerce empty to null. A caller that passes an unexpanded template
    // variable or empty flag would otherwise land on the idempotent path
    // keyed on `''` and inherit a stranger's patch.
    final normalizedClientPatchId =
        (clientPatchId == null || clientPatchId.isEmpty) ? null : clientPatchId;
    final normalizedGitSha = (gitSha == null || gitSha.isEmpty) ? null : gitSha;
    final request = CreatePatchRequest(
      releaseId: releaseId,
      metadata: metadata,
      clientPatchId: normalizedClientPatchId,
      gitSha: normalizedGitSha,
    );
    final response = await _httpClient.post(
      Uri.parse('$_v1/apps/$appId/patches'),
      body: json.encode(request.toJson()),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    return CreatePatchResponse.fromJson(body);
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
    return exceptionBuilder(
      message: error.message,
      details: error.details,
      code: error.code,
    );
  }
}

extension on http.BaseResponse {
  /// Whether the response has a 2xx status code.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}
