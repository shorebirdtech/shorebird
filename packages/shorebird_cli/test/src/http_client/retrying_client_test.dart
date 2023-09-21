import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/http_client/retrying_client.dart';
import 'package:test/test.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  group('retryingHttpClient', () {
    test('returns a RetryClient', () {
      final client = retryingHttpClient(MockHttpClient());
      expect(client, isA<RetryClient>());
    });

    group('isRetryableException', () {
      test('returns true on HttpException', () {
        expect(
          isRetryableException(const HttpException(''), StackTrace.empty),
          isTrue,
        );
      });

      test('returns true on TlsException', () {
        expect(
          isRetryableException(const TlsException(), StackTrace.empty),
          isTrue,
        );
      });

      test('returns true on SocketException', () {
        expect(
          isRetryableException(const SocketException(''), StackTrace.empty),
          isTrue,
        );
      });

      test('returns true on WebSocketException', () {
        expect(
          isRetryableException(const WebSocketException(), StackTrace.empty),
          isTrue,
        );
      });

      test('returns true on http.ClientException', () {
        expect(
          isRetryableException(http.ClientException(''), StackTrace.empty),
          isTrue,
        );
      });

      test('returns false on arbitrary exception', () {
        expect(isRetryableException(Exception(), StackTrace.empty), isFalse);
      });
    });

    group('isRetryableResponse', () {
      test('returns true if status code is >= 500', () {
        expect(isRetryableResponse(http.Response('', 500)), isTrue);
      });

      test('returns false if status code is < 500', () {
        expect(isRetryableResponse(http.Response('', 404)), isFalse);
      });
    });
  });
}
