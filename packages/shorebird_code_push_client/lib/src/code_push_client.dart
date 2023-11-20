import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_client/src/version.dart';

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
    return _client.send(request..headers.addAll(CodePushClient.headers));
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

/// Based on the [IOClient] from the `http` package. The primary difference is
/// that this implementation uses `stream.addStream` instead of `stream.pipe`
/// to allow for progress reporting.
class _UploadProgressHttpClient extends http.BaseClient {
  _UploadProgressHttpClient([HttpClient? inner])
      : _inner = inner ?? HttpClient(),
        _uploadProgressController =
            StreamController<DataTransferProgress>.broadcast();

  /// The underlying `dart:io` HTTP client.
  HttpClient? _inner;

  final StreamController<DataTransferProgress> _uploadProgressController;

  Stream<DataTransferProgress> get progressStream =>
      _uploadProgressController.stream;

  /// Sends an HTTP request and asynchronously returns the response.
  @override
  Future<IOStreamedResponse> send(http.BaseRequest request) async {
    if (_inner == null) {
      throw Exception('HTTP request failed. Client is already closed.');
    }

    final stream = request.finalize();

    try {
      final ioRequest = (await _inner!.openUrl(request.method, request.url))
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..contentLength = (request.contentLength ?? -1)
        ..persistentConnection = request.persistentConnection;
      request.headers.forEach((name, value) {
        ioRequest.headers.set(name, value);
      });

      final totalBytes = request.contentLength ?? 0;
      var bytesTransferred = 0;

      await ioRequest.addStream(
        stream.map((chunk) {
          bytesTransferred += chunk.length;
          _uploadProgressController.add(
            DataTransferProgress(
              bytesTransferred: bytesTransferred,
              totalBytes: totalBytes,
              url: request.url,
            ),
          );
          return chunk;
        }),
      );

      final response = await ioRequest.close();

      final headers = <String, String>{};
      response.headers.forEach((key, values) {
        headers[key] = values.join(',');
      });

      return IOStreamedResponse(
        response.handleError(
          (Object error) {
            final httpException = error as HttpException;
            throw http.ClientException(
              httpException.message,
              httpException.uri,
            );
          },
          test: (error) => error is HttpException,
        ),
        response.statusCode,
        contentLength:
            response.contentLength == -1 ? null : response.contentLength,
        request: request,
        headers: headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        inner: response,
      );
    } on SocketException catch (error) {
      throw http.ClientException(error.message, request.url);
    } on HttpException catch (error) {
      throw http.ClientException(error.message, error.uri);
    }
  }

  /// Closes the client.
  ///
  /// Terminates all active connections. If a client remains unclosed, the Dart
  /// process may not terminate.
  @override
  void close() {
    if (_inner != null) {
      _inner!.close(force: true);
      _inner = null;
    }
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
        _uploadProgressClient = _UploadProgressHttpClient(),
        hostedUri = hostedUri ?? Uri.https('api.shorebird.dev');

  /// The standard headers applied to all requests.
  static const headers = <String, String>{'x-version': packageVersion};

  /// The default error message to use when an unknown error occurs.
  static const unknownErrorMessage = 'An unknown error occurred.';

  final http.Client _httpClient;

  final _UploadProgressHttpClient _uploadProgressClient;

  /// The hosted uri for the Shorebird CodePush API.
  final Uri hostedUri;

  Uri get _v1 => Uri.parse('$hostedUri/api/v1');

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
    ProgressCallback? onProgress,
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

    final uploadRequest = http.MultipartRequest('POST', Uri.parse(decoded.url))
      ..files.add(file);
    final streamSubscription =
        _uploadProgressClient.progressStream.listen(onProgress);

    final uploadResponse = await _uploadProgressClient.send(uploadRequest);

    await streamSubscription.cancel();

    if (uploadResponse.statusCode != HttpStatus.noContent) {
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
    ProgressCallback? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_v1/apps/$appId/releases/$releaseId/artifacts'),
    );

    final file = await http.MultipartFile.fromPath('file', artifactPath);

    final payload = CreateReleaseArtifactRequest(
      arch: arch,
      platform: platform,
      hash: hash,
      size: file.length,
      canSideload: canSideload,
    ).toJson().map((key, value) => MapEntry(key, '$value'));
    request.fields.addAll(payload);

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, body);
    }

    final decoded = CreateReleaseArtifactResponse.fromJson(
      json.decode(body) as Map<String, dynamic>,
    );

    final uploadRequest = MultipartRequest(
      'POST',
      Uri.parse(decoded.url),
      onProgress: (bytes, totalBytes) => print('$bytes / $totalBytes'),
    )..files.add(file);
    // final uploadRequest = http.MultipartRequest('POST', Uri.parse(decoded.url))
    //   ..files.add(file);

    // final streamSubscription =
    //     _uploadProgressClient.progressStream.listen(onProgress);

    final uploadResponse = await _httpClient.send(uploadRequest);

    // await streamSubscription.cancel();

    if (uploadResponse.statusCode != HttpStatus.noContent) {
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

    if (response.statusCode != HttpStatus.ok) {
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
    var uri = Uri.parse(
      '$_v1/apps/$appId/releases',
    );
    if (sideloadableOnly) {
      uri = uri.replace(
        queryParameters: {'sideloadable': 'true'},
      );
    }

    final response = await _httpClient.get(uri);

    if (response.statusCode != HttpStatus.ok) {
      throw _parseErrorResponse(response.statusCode, response.body);
    }

    final decoded = GetReleasesResponse.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
    return decoded.releases;
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

class MultipartRequest extends http.MultipartRequest {
  MultipartRequest(
    String method,
    Uri url, {
    this.onProgress,
  }) : super(method, url);

  final void Function(int bytes, int totalBytes)? onProgress;

  @override
  http.ByteStream finalize() {
    if (onProgress == null) return super.finalize();
    final byteStream = super.finalize();

    final totalBytes = contentLength;
    var bytes = 0;

    final transformer = StreamTransformer.fromHandlers(
      handleData: (List<int> data, EventSink<List<int>> sink) {
        bytes += data.length;
        onProgress?.call(bytes, totalBytes);
        sink.add(data);
      },
    );
    return http.ByteStream(byteStream.transform(transformer));
  }
}
