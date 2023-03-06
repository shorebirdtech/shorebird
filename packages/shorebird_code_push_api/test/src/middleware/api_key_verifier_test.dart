import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/middleware/middleware.dart';
import 'package:test/test.dart';

void main() {
  group('apiKeyVerifier', () {
    const keys = ['valid-key'];

    test('returns 401 if no key is provided', () async {
      final handler = const Pipeline()
          .addMiddleware(apiKeyVerifier())
          .addHandler((_) => Response.ok('OK'));

      final request = Request('GET', Uri.parse('http://localhost/'));
      final response = await handler(request);
      expect(response.statusCode, equals(HttpStatus.unauthorized));
    });

    test('returns 401 if key is invalid', () async {
      final handler = const Pipeline()
          .addMiddleware(apiKeyVerifier(keys: keys))
          .addHandler((_) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/'),
        headers: {'x-api-key': 'invalid-key'},
      );
      final response = await handler(request);
      expect(response.statusCode, equals(HttpStatus.unauthorized));
    });

    test('returns 200 if key is valid', () async {
      final handler = const Pipeline()
          .addMiddleware(apiKeyVerifier(keys: keys))
          .addHandler((_) => Response.ok('OK'));

      final request = Request(
        'GET',
        Uri.parse('http://localhost/'),
        headers: {'x-api-key': 'valid-key'},
      );
      final response = await handler(request);
      expect(response.statusCode, equals(HttpStatus.ok));
    });
  });
}
