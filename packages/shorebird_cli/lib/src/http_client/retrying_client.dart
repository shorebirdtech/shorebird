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
  return switch (exception.runtimeType) {
    const (http.ClientException) => true,
    const (HttpException) => true,
    const (TlsException) => true,
    const (SocketException) => true,
    const (WebSocketException) => true,
    _ => false,
  };
}

/// Returns `true` if the [response] is a retryable response.
bool isRetryableResponse(http.BaseResponse response) =>
    response.statusCode >= 500;
