import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group(RetryingClient, () {
    late http.Client httpClient;
    late RetryingClient retryingClient;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      retryingClient = RetryingClient(httpClient: httpClient);

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          HttpStatus.ok,
        ),
      );
    });

    group('asNonFinalizedRequest', () {
      test('returns the given request if it is not finalized', () {
        final request = http.Request('GET', Uri.parse('https://example.com'));
        expect(RetryingClient.asNonFinalizedRequest(request), equals(request));
      });

      test('returns a non-finalized copy of of a finalized http.Request', () {
        final request = http.Request('POST', Uri.parse('https://example.com'))
          ..body = 'body'
          ..encoding = utf8
          ..headers.addAll({'headerName': 'headerValue'})
          ..finalize();

        final copy =
            RetryingClient.asNonFinalizedRequest(request) as http.Request;
        expect(copy, isA<http.Request>());
        expect(copy, isNot(equals(request)));
        expect(copy.finalized, isFalse);
        expect(copy.contentLength, equals(request.contentLength));
        expect(copy.headers, equals(request.headers));
        expect(copy.method, equals(request.method));
        expect(copy.bodyBytes, equals(request.bodyBytes));
        expect(copy.encoding, equals(request.encoding));
      });

      test(
        '''returns a non-finalized copy of of a finalized http.MultipartRequest''',
        () {
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('https://example.com'),
          )
            ..headers.addAll({'headerName': 'headerValue'})
            ..fields.addAll({'foo': 'bar'})
            ..files.add(http.MultipartFile.fromString('file', 'contents'))
            ..finalize();

          final copy = RetryingClient.asNonFinalizedRequest(request)
              as http.MultipartRequest;
          expect(copy, isA<http.MultipartRequest>());
          expect(copy, isNot(equals(request)));
          expect(copy.finalized, isFalse);
          expect(copy.contentLength, equals(request.contentLength));
          expect(copy.headers, equals(request.headers));
          expect(copy.method, equals(request.method));
          expect(copy.fields, equals(request.fields));
          expect(copy.files, equals(request.files));
        },
      );

      test(
        '''throws an exception if the request is an unknown http.BaseRequest subclass''',
        () {
          final request = http.StreamedRequest(
            'GET',
            Uri.parse('https://example.com'),
          )..finalize();
          expect(
            () => RetryingClient.asNonFinalizedRequest(request),
            throwsA(isA<ArgumentError>()),
          );
        },
      );
    });

    group('shouldRetryOnException', () {
      test('returns true on HttpException', () {
        expect(
          RetryingClient.shouldRetryOnException(const HttpException('')),
          isTrue,
        );
      });

      test('returns true on TlsException', () {
        expect(
          RetryingClient.shouldRetryOnException(const TlsException()),
          isTrue,
        );
      });

      test('returns true on SocketException', () {
        expect(
          RetryingClient.shouldRetryOnException(const SocketException('')),
          isTrue,
        );
      });

      test('returns true on WebSocketException', () {
        expect(
          RetryingClient.shouldRetryOnException(const WebSocketException()),
          isTrue,
        );
      });

      test(
        'returns true on CodePushExeption if status code is 500 or greater',
        () {
          const exception = CodePushException(message: '', statusCode: 500);
          expect(RetryingClient.shouldRetryOnException(exception), isTrue);
        },
      );

      test(
        'returns false on CodePushExeption if status code is less than 500',
        () {
          const exception = CodePushException(message: '', statusCode: 404);
          expect(RetryingClient.shouldRetryOnException(exception), isFalse);
        },
      );

      test('returns false on arbitrary exception', () {
        expect(RetryingClient.shouldRetryOnException(Exception()), isFalse);
      });
    });

    test('does not retry successful request', () {
      expect(
        () => retryingClient.send(
          http.Request('GET', Uri.parse('https://example.com')),
        ),
        returnsNormally,
      );
    });

    test('retries on exception', () async {
      var hasThrown = false;
      when(() => httpClient.send(any())).thenAnswer(
        (_) async {
          if (!hasThrown) {
            hasThrown = true;
            throw const SocketException('');
          }

          return http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.ok,
          );
        },
      );

      await retryingClient.send(
        http.Request('GET', Uri.parse('https://example.com')),
      );

      verify(() => httpClient.send(any())).called(2);
    });
  });
}
