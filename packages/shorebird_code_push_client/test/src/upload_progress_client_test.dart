import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements HttpClient {}

class _MockHttpClientRequest extends Mock implements HttpClientRequest {}

class _MockHttpClientResponse extends Mock implements HttpClientResponse {}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  @override
  void forEach(void Function(String name, List<String> values) action) {
    action('content-length', ['42']);
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

void main() {
  group(UploadProgressHttpClient, () {
    final url = Uri.parse('https://example.com');

    late HttpClient innerClient;
    late HttpClientRequest ioRequest;
    late HttpClientResponse innerResponse;
    late HttpHeaders headers;
    late http.MultipartRequest request;
    late UploadProgressHttpClient client;

    setUpAll(() {
      registerFallbackValue(const Stream<List<int>>.empty());
      registerFallbackValue(url);
    });

    setUp(() async {
      innerClient = _MockHttpClient();
      ioRequest = _MockHttpClientRequest();
      client = UploadProgressHttpClient(innerClient);
      headers = _FakeHttpHeaders();
      innerResponse = _MockHttpClientResponse();

      final tempDir = Directory.systemTemp.createTempSync();
      final file = File(p.join(tempDir.path, 'test.txt'))
        ..writeAsStringSync('1');
      final multipartFile =
          await http.MultipartFile.fromPath('file', file.path);
      request = http.MultipartRequest('POST', url)..files.add(multipartFile);

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
        test('argument to handle error throws ClientException', () async {
          await client.send(request);
          final captured = verify(
            () => innerResponse.handleError(
              captureAny(),
              test: captureAny(named: 'test'),
            ),
          ).captured;
          final onError = captured.first as void Function(Object);
          expect(
            () => onError(const HttpException('HttpException')),
            throwsA(isA<http.ClientException>()),
          );
        });

        test('handleError test function returns true if error is HttpException',
            () async {
          await client.send(request);
          final captured = verify(
            () => innerResponse.handleError(
              captureAny(),
              test: captureAny(named: 'test'),
            ),
          ).captured;
          final test = captured.last as bool Function(Object);
          expect(test(Exception('not an HttpException')), isFalse);
          expect(test(const HttpException('HttpException')), isTrue);
        });

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

    group('progressStream', () {
      late Stream<List<int>> capturedStream;

      setUp(() {
        when(() => ioRequest.addStream(any())).thenAnswer((invocation) async {
          capturedStream =
              invocation.positionalArguments.first as Stream<List<int>>;
        });
      });

      test('reports progress as transfer occurs', () async {
        expect(
          client.progressStream,
          emitsInOrder([
            DataTransferProgress(
              bytesTransferred: 74,
              totalBytes: 261,
              url: url,
            ),
            DataTransferProgress(
              bytesTransferred: 182,
              totalBytes: 261,
              url: url,
            ),
          ]),
        );

        await client.send(request);

        // Cause the stream to be consumed.
        await capturedStream.toList();
      });
    });

    group('close', () {
      test('closes inner client', () {
        client.close();
        verify(() => innerClient.close(force: true)).called(1);
      });
    });
  });
}
