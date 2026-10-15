import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/http_client/retrying_client.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
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

    group('when retries are turned off', () {
      setUpAll(() => registerFallbackValue(http.Request('GET', Uri())));

      R withoutRetries<R>(R Function() body) => runScoped(
        body,
        values: {retryFailedRequestsRef.overrideWith(() => false)},
      );

      test('does not retry a failed response or exception', () {
        withoutRetries(() {
          expect(
            isRetryableResponse(http.Response('', HttpStatus.badGateway)),
            isFalse,
          );
          expect(
            isRetryableException(const SocketException(''), StackTrace.empty),
            isFalse,
          );
        });
      });

      test('sends a request that fails once', () async {
        final inner = MockHttpClient();
        when(() => inner.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.serviceUnavailable,
          ),
        );
        final client = retryingHttpClient(inner);

        final response = await withoutRetries(
          () => client.send(http.Request('POST', Uri.parse('https://x.dev'))),
        );

        expect(response.statusCode, equals(HttpStatus.serviceUnavailable));
        verify(() => inner.send(any())).called(1);
      });
    });
  });
}
