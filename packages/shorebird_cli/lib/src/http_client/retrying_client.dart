import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

/// An http client that retries requests on connection failures.
http.Client retryingHttpClient(http.Client client) => RetryClient(
      client,
      when: (response) => response.statusCode >= 500,
      whenError: (e, _) {
        return switch (e.runtimeType) {
          HttpException => true,
          TlsException => true,
          SocketException => true,
          WebSocketException => true,
          _ => false,
        };
      },
    );
