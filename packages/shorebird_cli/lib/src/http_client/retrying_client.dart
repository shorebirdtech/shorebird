import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// Whether requests sent in the current zone are retried on failure.
///
/// The retrying client is shared and built once, so a caller that must not
/// send a request twice (a write that may already have reached the server)
/// turns retries off for its own requests by overriding this with false.
final retryFailedRequestsRef = create(() => true);

bool get _retriesEnabled => read(retryFailedRequestsRef, orElse: () => true);

/// The request methods RFC 9110 (section 9.2.2) defines as idempotent: sending
/// one twice has the same effect on the server as sending it once.
const idempotentMethods = {'GET', 'HEAD', 'OPTIONS', 'TRACE', 'PUT', 'DELETE'};

/// An http client that retries idempotent requests on connection failures and
/// 5xx responses.
///
/// A POST or PATCH is sent once: a failed response or a dropped connection
/// does not tell us the server didn't act on it, and sending it again can
/// repeat the write (for example, create a release the first attempt already
/// created). Callers that know a write is safe to repeat retry it themselves.
http.Client retryingHttpClient(http.Client client) =>
    IdempotentRetryClient(client);

/// Sends [idempotentMethods] through a [RetryClient] and every other request
/// straight to the inner client.
class IdempotentRetryClient extends http.BaseClient {
  /// Creates an [IdempotentRetryClient] wrapping [_inner]. [delay] is how
  /// long to wait before each retry, [RetryClient]'s backoff by default.
  IdempotentRetryClient(this._inner, {Duration Function(int retryCount)? delay})
    : _retrying = delay == null
          ? RetryClient(
              _inner,
              when: isRetryableResponse,
              whenError: isRetryableException,
            )
          : RetryClient(
              _inner,
              when: isRetryableResponse,
              whenError: isRetryableException,
              delay: delay,
            );

  final http.Client _inner;
  final RetryClient _retrying;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      idempotentMethods.contains(request.method.toUpperCase())
      ? _retrying.send(request)
      : _inner.send(request);

  // Closing the RetryClient closes the inner client too.
  @override
  void close() => _retrying.close();
}

/// Returns `true` if the [exception] is a retryable exception.
bool isRetryableException(Object exception, StackTrace _) {
  if (!_retriesEnabled) return false;
  switch (exception) {
    case http.ClientException():
    case HttpException():
    case TlsException():
    case SocketException():
    case WebSocketException():
      return true;
    default:
      return false;
  }
}

/// Returns `true` if the [response] is a retryable response.
bool isRetryableResponse(http.BaseResponse response) =>
    _retriesEnabled && response.statusCode >= 500;
