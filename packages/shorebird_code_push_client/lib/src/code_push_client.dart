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
  const CodePushException({
    required this.message,
    this.details,
    this.statusCode,
    this.response,
  });

  /// The message associated with the exception.
  final String message;

  /// The details associated with the exception.
  final String? details;

  /// The HTTP status code of the failed response, or null when the failure
  /// did not come from an HTTP response.
  final int? statusCode;

  /// The server's [ErrorResponse], or null when the response body was not
  /// one.
  final ErrorResponse? response;

  /// The machine-readable error code from the server's [ErrorResponse]
  /// (e.g. `shorebird_plan_insufficient_tier`), or null when the response
  /// body was not an [ErrorResponse].
  String? get code => response?.code;

  /// A page documenting the API and its errors, from the server's
  /// [ErrorResponse], or null when the server did not send one.
  Uri? get documentationUrl => response?.documentationUrl;

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
    super.statusCode,
    super.response,
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
    super.statusCode,
    super.response,
  });
}

/// {@template code_push_not_found_exception}
/// Exception thrown when a 404 response is received.
/// {@endtemplate}
class CodePushNotFoundException extends CodePushException {
  /// {@macro code_push_not_found_exception}
  CodePushNotFoundException({
    required super.message,
    super.details,
    super.statusCode,
    super.response,
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
    super.statusCode,
    super.response,
  });
}

/// {@template code_push_upload_exception}
/// Exception thrown when uploading an artifact's bytes to storage fails.
///
/// [statusCode] is the storage service's, not the Shorebird API's, so this is
/// never one of the API status exceptions (a storage 409 is not an API
/// conflict).
/// {@endtemplate}
class CodePushUploadException extends CodePushException {
  /// {@macro code_push_upload_exception}
  const CodePushUploadException({required super.message, super.statusCode});
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

  /// The message used when the server returns a non-2xx response whose body is
  /// not a JSON [ErrorResponse] -- typically an HTML or plain-text error page
  /// served by Cloud Run or the load balancer rather than by our API. The
  /// status code is the only thing that distinguishes these failures from one
  /// another, so it belongs in the message.
  @visibleForTesting
  static String unknownErrorMessageFor(int statusCode) =>
      '$unknownErrorMessage (HTTP $statusCode)';

  /// The maximum number of characters of an unparseable error body to surface
  /// as exception details.
  static const _maxUnknownErrorBodyLength = 200;

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

  Uri get _v1 => apiBaseUri;

  /// The base URI of every API route: [hostedUri] followed by `/api/v1`.
  Uri get apiBaseUri => Uri.parse('$hostedUri/api/v1');

  /// Sends [request] as-is, with the headers and authentication every other
  /// method on this client uses, and returns the response unchecked.
  ///
  /// For callers that build their own requests, such as `shorebird api`.
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _httpClient.send(request);

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

  /// Fetches the plan level for the currently logged-in user, e.g. `free`,
  /// `pro`, `business` or `enterprise`.
  ///
  /// The plan itself is a server-local model with billing fields that are
  /// deliberately not part of this package, so only the level is read here.
  /// Returns null if the server does not report one.
  Future<String?> getPlanLevel() async {
    final response = await _httpClient.get(Uri.parse('$_v1/plan'));

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['level'] as String?;
  }

  /// Sets the currently logged-in user's display name to [displayName].
  Future<void> updateCurrentUser({required String displayName}) async {
    final response = await _httpClient.patch(
      Uri.parse('$_v1/users/me'),
      body: json.encode({'display_name': displayName}),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Whether the currently logged-in user receives email notifications.
  Future<bool> getEmailNotificationsEnabled() async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/users/me/notification_preferences'),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final preferences = body['preferences'] as Map<String, dynamic>;
    return preferences['are_email_notifications_enabled'] as bool;
  }

  /// Turns the currently logged-in user's email notifications on or off.
  Future<void> setEmailNotificationsEnabled({required bool enabled}) async {
    final response = await _httpClient.patch(
      Uri.parse('$_v1/users/me/notification_preferences'),
      body: json.encode({'are_email_notifications_enabled': enabled}),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
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
  CodePushUploadException _uploadFailed(http.BaseResponse response) {
    final reason = response.reasonPhrase;
    return CodePushUploadException(
      message: 'Failed to upload artifact ($reason ${response.statusCode})',
      statusCode: response.statusCode,
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

  /// Deletes the release with the provided [releaseId], along with every
  /// platform's artifacts and every patch belonging to it.
  Future<void> deleteRelease({
    required String appId,
    required int releaseId,
  }) async {
    final response = await _httpClient.delete(
      Uri.parse('$_v1/apps/$appId/releases/$releaseId'),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Deletes the [platform] artifacts of the release with the provided
  /// [releaseId], removing [platform] from the release.
  ///
  /// The release and its other platforms are left in place.
  Future<void> deleteReleaseArtifacts({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
  }) async {
    final response = await _httpClient.delete(
      Uri.parse(
        '$_v1/apps/$appId/releases/$releaseId/artifacts',
      ).replace(queryParameters: {'platform': platform.value}),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Delete the app with the provided [appId].
  Future<void> deleteApp({required String appId}) async {
    final response = await _httpClient.delete(Uri.parse('$_v1/apps/$appId'));

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Rename the app with the provided [appId] to [displayName].
  Future<void> updateApp({
    required String appId,
    required String displayName,
  }) async {
    final response = await _httpClient.patch(
      Uri.parse('$_v1/apps/$appId'),
      body: json.encode({'name': displayName}),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Move the app with the provided [appId] into [organizationId].
  ///
  /// Requires permission to transfer apps in both the source and destination
  /// organizations.
  Future<void> transferApp({
    required int organizationId,
    required String appId,
  }) async {
    final response = await _httpClient.post(
      Uri.parse('$_v1/organizations/$organizationId/apps'),
      body: json.encode({'app_id': appId}),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Delete the channel with the provided [channelId] from [appId].
  Future<void> deleteChannel({
    required String appId,
    required int channelId,
  }) async {
    final response = await _httpClient.delete(
      Uri.parse('$_v1/apps/$appId/channels/$channelId'),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
  }

  /// Fetches the app with the provided [appId], or `null` if no such app is
  /// visible to the current account.
  ///
  /// Prefer this over filtering [getApps] when the app id is already known:
  /// [getApps] returns every app on the account, which is unbounded.
  Future<AppMetadata?> getApp({required String appId}) async {
    final response = await _httpClient.get(Uri.parse('$_v1/apps/$appId'));

    if (response.statusCode == HttpStatus.notFound) return null;
    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    return AppMetadata.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
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

  /// Rolls back the patch with [patchId] under [releaseId] for [appId].
  ///
  /// Devices on the affected release_version that next call the patch-check
  /// endpoint will receive the patch number in `rolled_back_patch_numbers`,
  /// which signals the updater to revert to the prior patch (or the base
  /// release if none).
  ///
  /// Idempotent. Returns whether the server changed the patch: `false` when it
  /// answers `304 Not Modified` because the patch was already rolled back,
  /// `true` when it changed the patch. The server is the only authority on
  /// this, since another actor may roll the patch back between a read and this
  /// call.
  Future<bool> rollbackPatch({
    required String appId,
    required int releaseId,
    required int patchId,
  }) async {
    final response = await _httpClient.post(
      Uri.parse(
        '$_v1/apps/$appId/releases/$releaseId/patches/$patchId/rollback',
      ),
    );

    if (response.statusCode == HttpStatus.notModified) return false;
    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
    return true;
  }

  /// Rolls forward (un-rolls-back) the patch with [patchId] under [releaseId]
  /// for [appId]. The server flips `is_rolled_back` from `true` to `false`
  /// on the same patch row, so the same patch artifact (same hash) becomes
  /// active again.
  ///
  /// Idempotent. Returns whether the server changed the patch: `false` when it
  /// answers `304 Not Modified` because the patch was already active, `true`
  /// when it changed the patch. The server is the only authority on this, since
  /// another actor may roll the patch forward between a read and this call.
  Future<bool> rollforwardPatch({
    required String appId,
    required int releaseId,
    required int patchId,
  }) async {
    final response = await _httpClient.post(
      Uri.parse(
        '$_v1/apps/$appId/releases/$releaseId/patches/$patchId/rollforward',
      ),
    );

    if (response.statusCode == HttpStatus.notModified) return false;
    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }
    return true;
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

  /// Gets the apps in organization [organizationId] that the user can see.
  Future<List<AppMetadata>> getOrganizationApps({
    required int organizationId,
  }) async {
    final response = await _httpClient.get(
      Uri.parse('$_v1/organizations/$organizationId/apps'),
    );

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    return GetOrganizationAppsResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    ).apps;
  }

  /// Gets the pending invitations sent to the current user, most recently
  /// sent first, following every page.
  Future<List<ReceivedInvitation>> getReceivedInvitations() async {
    final invitations = <ReceivedInvitation>[];
    String? cursor;
    do {
      final response = await _httpClient.get(
        Uri.parse('$_v1/invitations').replace(
          queryParameters: {'per_page': '100', 'cursor': ?cursor},
        ),
      );

      if (!response.isSuccess) {
        throw _parseErrorResponse(response.statusCode, response.body);
      }

      final page = GetReceivedInvitationsResponse.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
      invitations.addAll(page.invitations);
      // An empty page ends the list even if it carries a cursor, so a
      // misbehaving server cannot keep this loop going.
      cursor = page.invitations.isEmpty ? null : page.nextCursor;
    } while (cursor != null);
    return invitations;
  }

  /// Accepts the invitation with [invitationId], which must have been sent
  /// to the current user.
  Future<void> acceptInvitation({required String invitationId}) =>
      _respondToInvitation(invitationId: invitationId, response: 'accept');

  /// Declines the invitation with [invitationId], which must have been sent
  /// to the current user.
  Future<void> declineInvitation({required String invitationId}) =>
      _respondToInvitation(invitationId: invitationId, response: 'decline');

  Future<void> _respondToInvitation({
    required String invitationId,
    required String response,
  }) async {
    final httpResponse = await _httpClient.post(
      Uri.parse(
        '$_v1/invitations/${Uri.encodeComponent(invitationId)}/$response',
      ),
    );

    if (!httpResponse.isSuccess) {
      throw _parseErrorResponse(httpResponse.statusCode, httpResponse.body);
    }
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

  /// Fetches patch installs for [appId] over a time window.
  ///
  /// [start] and [end] bound the window (server defaults: the 28 days ending
  /// now). [granularity] (`hour`, `day` or `week`) adds a `time_series`;
  /// [groupBy] (`release`) adds a per-release `breakdown`.
  Future<GetPatchMetricResponse> getAppPatchInstalls({
    required String appId,
    DateTime? start,
    DateTime? end,
    String? granularity,
    String? groupBy,
  }) => _getPatchMetric(
    path: 'apps/$appId/metrics/patch-installs',
    start: start,
    end: end,
    granularity: granularity,
    groupBy: groupBy,
  );

  /// Fetches patch installs for release [releaseId] of [appId] over a time
  /// window.
  ///
  /// Parameters are as for [getAppPatchInstalls], except that [groupBy]
  /// accepts `patch`.
  Future<GetPatchMetricResponse> getReleasePatchInstalls({
    required String appId,
    required int releaseId,
    DateTime? start,
    DateTime? end,
    String? granularity,
    String? groupBy,
  }) => _getPatchMetric(
    path: 'apps/$appId/releases/$releaseId/metrics/patch-installs',
    start: start,
    end: end,
    granularity: granularity,
    groupBy: groupBy,
  );

  /// Fetches patch downloads for [appId] over a time window.
  ///
  /// Parameters are as for [getAppPatchInstalls].
  Future<GetPatchMetricResponse> getAppPatchDownloads({
    required String appId,
    DateTime? start,
    DateTime? end,
    String? granularity,
    String? groupBy,
  }) => _getPatchMetric(
    path: 'apps/$appId/metrics/patch-downloads',
    start: start,
    end: end,
    granularity: granularity,
    groupBy: groupBy,
  );

  /// Fetches patch downloads for release [releaseId] of [appId] over a time
  /// window.
  ///
  /// Parameters are as for [getReleasePatchInstalls].
  Future<GetPatchMetricResponse> getReleasePatchDownloads({
    required String appId,
    required int releaseId,
    DateTime? start,
    DateTime? end,
    String? granularity,
    String? groupBy,
  }) => _getPatchMetric(
    path: 'apps/$appId/releases/$releaseId/metrics/patch-downloads',
    start: start,
    end: end,
    granularity: granularity,
    groupBy: groupBy,
  );

  Future<GetPatchMetricResponse> _getPatchMetric({
    required String path,
    required DateTime? start,
    required DateTime? end,
    required String? granularity,
    required String? groupBy,
  }) => _getMetric(
    path,
    queryParameters: {
      ..._windowParameters(start: start, end: end),
      'granularity': ?granularity,
      'group_by': ?groupBy,
    },
    fromJson: GetPatchMetricResponse.fromJson,
  );

  /// Fetches the number of unique users (devices) of [appId] over a time
  /// window.
  ///
  /// [start] and [end] bound the window (server defaults: the 28 days ending
  /// now). [granularity] (`hour`, `day` or `week`) adds a `time_series`;
  /// [groupBy] (`platform` or `release_version`) adds a `breakdown`.
  Future<GetUniqueUsersResponse> getUniqueUsers({
    required String appId,
    DateTime? start,
    DateTime? end,
    String? granularity,
    String? groupBy,
  }) => _getMetric(
    'apps/$appId/metrics/unique-users',
    queryParameters: {
      ..._windowParameters(start: start, end: end),
      'granularity': ?granularity,
      'group_by': ?groupBy,
    },
    fromJson: GetUniqueUsersResponse.fromJson,
  );

  /// Fetches how [appId]'s currently-active devices are distributed across
  /// release versions.
  Future<GetVersionDistributionResponse> getVersionDistribution({
    required String appId,
  }) => _getMetric(
    'apps/$appId/metrics/version-distribution',
    fromJson: GetVersionDistributionResponse.fromJson,
  );

  /// Fetches the number of devices first seen running [appId] recently,
  /// compared with the preceding window.
  Future<GetNewDevicesResponse> getNewDevices({required String appId}) =>
      _getMetric(
        'apps/$appId/metrics/new-devices',
        fromJson: GetNewDevicesResponse.fromJson,
      );

  /// Fetches per-patch adoption for release [releaseVersion] of [appId] (the
  /// app's latest release when null).
  ///
  /// [start] and [end] bound the window (server defaults: the 28 days ending
  /// now). [granularity] (`hour`, `day` or `week`) returns one point per
  /// bucket instead of a single full-window value.
  Future<GetPatchAdoptionResponse> getPatchAdoption({
    required String appId,
    String? releaseVersion,
    DateTime? start,
    DateTime? end,
    String? granularity,
  }) => _getMetric(
    'apps/$appId/metrics/patch-adoption',
    queryParameters: {
      'release_version': ?releaseVersion,
      ..._windowParameters(start: start, end: end),
      'granularity': ?granularity,
    },
    fromJson: GetPatchAdoptionResponse.fromJson,
  );

  /// Fetches the average number of active devices of [appId] for each UTC
  /// hour of the day, with a recommended low-activity release window.
  Future<GetActiveHoursResponse> getActiveHours({required String appId}) =>
      _getMetric(
        'apps/$appId/metrics/active-hours',
        fromJson: GetActiveHoursResponse.fromJson,
      );

  /// Fetches the average number of active devices of [appId] for each
  /// (UTC day of week, UTC hour of day) pair.
  Future<GetActivityHeatmapResponse> getActivityHeatmap({
    required String appId,
  }) => _getMetric(
    'apps/$appId/metrics/activity-heatmap',
    fromJson: GetActivityHeatmapResponse.fromJson,
  );

  /// The `start`/`end` query parameters for a metrics window, as UTC ISO 8601
  /// timestamps. Omitted when null so the server applies its defaults.
  static Map<String, String> _windowParameters({
    required DateTime? start,
    required DateTime? end,
  }) => {
    if (start != null) 'start': start.toUtc().toIso8601String(),
    if (end != null) 'end': end.toUtc().toIso8601String(),
  };

  Future<T> _getMetric<T>(
    String path, {
    required T Function(Map<String, dynamic>) fromJson,
    Map<String, String> queryParameters = const {},
  }) async {
    var uri = Uri.parse('$_v1/$path');
    if (queryParameters.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    final response = await _httpClient.get(uri);

    if (!response.isSuccess) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    return fromJson(json.decode(response.body) as Map<String, dynamic>);
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
      throw exceptionBuilder(
        message: unknownErrorMessageFor(statusCode),
        details: _truncateBody(response),
        statusCode: statusCode,
      );
    }
    return exceptionBuilder(
      message: error.message,
      details: error.details,
      statusCode: statusCode,
      response: error,
    );
  }

  /// Returns a single-line, length-capped form of [body], or `null` if there is
  /// nothing useful to show.
  static String? _truncateBody(String body) {
    final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return null;
    if (collapsed.length <= _maxUnknownErrorBodyLength) return collapsed;
    return '${collapsed.substring(0, _maxUnknownErrorBodyLength)}...';
  }
}

extension on http.BaseResponse {
  /// Whether the response has a 2xx status code.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}
