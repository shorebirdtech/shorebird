import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:shorebird_code_push_api/src/routes/download_engine/download_engine.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('downloadEngineHandler', () {
    final uri = Uri.parse('http://localhost/');
    late http.Client httpClient;

    setUpAll(() {
      registerFallbackValue(Uri());
    });

    setUp(() {
      httpClient = _MockHttpClient();
    });

    test('returns error on failure', () async {
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('oops', HttpStatus.unauthorized));
      final request = Request('GET', uri).provide(() async => httpClient);

      final response = await downloadEngineHandler(request, 'revision');
      expect(response.statusCode, equals(HttpStatus.unauthorized));
    });

    test('returns bytes on success', () async {
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('OK', HttpStatus.ok));
      final request = Request('GET', uri).provide(() async => httpClient);

      final response = await downloadEngineHandler(request, 'revision');
      expect(response.statusCode, equals(HttpStatus.ok));
    });
  });
}
