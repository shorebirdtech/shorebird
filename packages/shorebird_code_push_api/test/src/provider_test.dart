import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:test/test.dart';

void main() {
  test('values can be provided and read via middleware', () async {
    const value = '__test_value__';
    Handler middleware(Handler handler) {
      return (request) {
        return handler(request.provide(() => value));
      };
    }

    Response onRequest(Request request) {
      final value = request.lookup<String>();
      return Response.ok(value);
    }

    final handler =
        const Pipeline().addMiddleware(middleware).addHandler(onRequest);

    final request = Request('GET', Uri.parse('http://localhost/'));
    final response = await handler(request);

    await expectLater(response.statusCode, equals(HttpStatus.ok));
    await expectLater(await response.readAsString(), equals(value));
  });

  test('A StateError is thrown when reading an un-provided value', () async {
    Response onRequest(Request request) {
      request.lookup<Uri>();
      return Response.ok('');
    }

    final handler = const Pipeline()
        .addMiddleware((handler) => handler)
        .addHandler(onRequest);

    final request = Request('GET', Uri.parse('http://localhost/'));

    await expectLater(() => handler(request), throwsStateError);
  });
}
