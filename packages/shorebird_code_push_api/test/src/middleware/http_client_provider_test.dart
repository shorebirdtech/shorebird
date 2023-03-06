import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/middleware/middleware.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:test/test.dart';

void main() {
  group('httpClientProvider', () {
    test('provides an http client instance', () async {
      Future<http.Client>? client;

      final handler = httpClientProvider('')(
        (req) async {
          client = req.lookup<Future<http.Client>>();
          return Response.ok('');
        },
      );
      final request = Request('GET', Uri.parse('http://localhost/'));

      await handler(request);
      expect(client, isNotNull);
    });
  });
}
