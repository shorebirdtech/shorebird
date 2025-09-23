import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

/// An http client that retries requests on connection failures.
http.Client retryingHttpClient(http.Client client) => RetryClient(
  client,
  when: isRetryableResponse,
  whenError: isRetryableException,
);

/// Returns `true` if the [exception] is a retryable exception.
bool isRetryableException(Object exception, StackTrace _) {
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
    response.statusCode >= 500;
