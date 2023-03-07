import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:shorebird_code_push_api/src/routes/download_engine/download_engine.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  group('downloadEngineHandler', () {
    final uri = Uri.parse('http://localhost/');
    late http.Client httpClient;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      httpClient = _MockHttpClient();
    });

    test('returns error on failure', () async {
      when(
        () => httpClient.send(any()),
      ).thenAnswer((_) async {
        return http.StreamedResponse(
          const Stream.empty(),
          HttpStatus.unauthorized,
        );
      });
      final request = Request('GET', uri).provide(() => httpClient);

      final response = await downloadEngineHandler(request, 'revision');
      expect(response.statusCode, equals(HttpStatus.unauthorized));
    });

    test('returns bytes on success', () async {
      when(
        () => httpClient.send(any()),
      ).thenAnswer((_) async {
        return http.StreamedResponse(
          const Stream.empty(),
          HttpStatus.ok,
        );
      });
      final request = Request('GET', uri).provide(() => httpClient);

      final response = await downloadEngineHandler(request, 'revision');
      expect(response.statusCode, equals(HttpStatus.ok));
    });
  });
}
