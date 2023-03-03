import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/middleware/middleware.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:shorebird_code_push_api/src/version_store.dart';
import 'package:test/test.dart';

void main() {
  group('versionStoreProvider', () {
    test('provides a version store instance', () async {
      VersionStore? store;

      final handler = versionStoreProvider(
        (req) {
          store = req.lookup<VersionStore>();
          return Response.ok('');
        },
      );
      final request = Request('GET', Uri.parse('http://localhost/'));

      await handler(request);
      expect(store, isNotNull);
    });
  });
}
