import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockHttpHeaders extends Mock implements HttpHeaders {}

class _MockHttpClient extends Mock implements HttpClient {}

class _MockHttpClientRequest extends Mock implements HttpClientRequest {}

class _MockHttpClientResponse extends Mock implements HttpClientResponse {}

void main() {
  group(UploadProgressHttpClient, () {
    late HttpClient innerClient;
    late HttpClientRequest ioRequest;
    late HttpClientResponse innerResponse;
    late HttpHeaders headers;
    late http.MultipartRequest request;
    late UploadProgressHttpClient client;

    setUpAll(() {
      registerFallbackValue(const Stream<List<int>>.empty());
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      innerClient = _MockHttpClient();
      ioRequest = _MockHttpClientRequest();
      client = UploadProgressHttpClient(innerClient);
      headers = _MockHttpHeaders();
      innerResponse = _MockHttpClientResponse();
      request = http.MultipartRequest('POST', Uri.parse('https://example.com'));

      when(() => innerClient.openUrl(any(), any()))
          .thenAnswer((_) async => ioRequest);
      when(() => ioRequest.addStream(any())).thenAnswer((_) async => {});
      when(() => ioRequest.close()).thenAnswer((_) async => innerResponse);
      when(() => ioRequest.followRedirects).thenReturn(true);
      when(() => ioRequest.maxRedirects).thenReturn(42);
      when(() => ioRequest.contentLength).thenReturn(42);
      when(() => ioRequest.persistentConnection).thenReturn(true);
      when(() => ioRequest.headers).thenReturn(headers);

      when(() => innerResponse.headers).thenReturn(headers);
      when(() => innerResponse.handleError(any(), test: any(named: 'test')))
          .thenAnswer((_) => const Stream.empty());
      when(() => innerResponse.contentLength).thenReturn(42);
      when(() => innerResponse.statusCode).thenReturn(HttpStatus.ok);
      when(() => innerResponse.isRedirect).thenReturn(false);
      when(() => innerResponse.persistentConnection).thenReturn(false);
      when(() => innerResponse.reasonPhrase).thenReturn('reason phrase');
    });

    group('send', () {
      group('when SocketException is raised', () {
        setUp(() {
          when(() => innerClient.openUrl(any(), any()))
              .thenThrow(const SocketException('SocketException'));
        });

        test('throws ClientException', () async {
          expect(client.send(request), throwsA(isA<http.ClientException>()));
        });
      });

      group('when HttpException is raised', () {
        setUp(() {
          when(() => innerClient.openUrl(any(), any()))
              .thenThrow(const HttpException('HttpException'));
        });

        test('throws ClientException', () async {
          expect(client.send(request), throwsA(isA<http.ClientException>()));
        });
      });

      group('when no errors are thrown', () {
        test('returns streamed response', () async {
          final response = await client.send(request);
          expect(response, isA<IOStreamedResponse>());
          expect(response.contentLength, innerResponse.contentLength);
          expect(response.isRedirect, innerResponse.isRedirect);
          expect(
            response.persistentConnection,
            innerResponse.persistentConnection,
          );
          expect(response.reasonPhrase, innerResponse.reasonPhrase);
        });
      });
    });
  });
}
