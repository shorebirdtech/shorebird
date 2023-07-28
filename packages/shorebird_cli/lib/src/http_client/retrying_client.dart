import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:meta/meta.dart';

/// An http client that retries requests on connection failures.
http.Client retryingHttpClient(http.Client client) => RetryClient(
      client,
      when: isRetryableResponse,
      whenError: isRetryableException,
    );

@visibleForTesting
bool isRetryableException(Object exception, StackTrace _) {
  return switch (exception.runtimeType) {
    HttpException => true,
    TlsException => true,
    SocketException => true,
    WebSocketException => true,
    _ => false,
  };
}

@visibleForTesting
bool isRetryableResponse(http.BaseResponse response) =>
    response.statusCode >= 500;
