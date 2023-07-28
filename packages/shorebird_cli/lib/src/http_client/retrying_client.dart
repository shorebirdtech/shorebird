import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

/// An http client that retries requests on connection failures.
class RetryingClient extends http.BaseClient {
  RetryingClient({required http.Client httpClient}) : _baseClient = httpClient;

  final http.Client _baseClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => retry(
        () => _baseClient.send(
          _asNonFinalizedRequest(request),
        ),
        retryIf: _shouldRetryOnException,
      );

  /// Because [http.Client.send] finalizes requests and requires a non-finalized
  /// request as a parameter, we need to create a non-finalized copy to support
  /// retries.
  http.BaseRequest _asNonFinalizedRequest(http.BaseRequest request) {
    if (!request.finalized) {
      return request;
    }

    if (request is http.Request) {
      return http.Request(request.method, request.url)
        ..bodyBytes = request.bodyBytes
        ..encoding = request.encoding
        ..headers.addAll(request.headers);
    }

    if (request is http.MultipartRequest) {
      return http.MultipartRequest(request.method, request.url)
        ..fields.addAll(request.fields)
        ..files.addAll(request.files)
        ..headers.addAll(request.headers);
    }

    throw ArgumentError.value(
      request,
      'request',
      'Request must be either a Request or MultipartRequest.',
    );
  }

  bool _shouldRetryOnException(Object e) =>
      e is HttpException ||
      e is TlsException ||
      e is SocketException ||
      e is WebSocketException;
}
