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

/// An http client that retries requests on connection failures.
http.Client retryingHttpClient(http.Client client) => RetryClient(
  client,
  when: isRetryableResponse,
  whenError: isRetryableException,
);

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
