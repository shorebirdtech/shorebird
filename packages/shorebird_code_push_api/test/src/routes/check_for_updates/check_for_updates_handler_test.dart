import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:shorebird_code_push_api/src/provider.dart';
import 'package:shorebird_code_push_api/src/routes/check_for_updates/check_for_updates.dart';
import 'package:shorebird_code_push_api/src/version_store.dart';
import 'package:test/test.dart';

class _MockVersionStore extends Mock implements VersionStore {}

void main() {
  group('checkForUpdatesHandler', () {
    final uri = Uri.parse('http://localhost/');

    late VersionStore store;

    setUp(() {
      store = _MockVersionStore();
    });

    test('returns 400 if request body is invalid', () async {
      final request = Request('POST', uri);
      final response = await checkForUpdatesHandler(request);

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test(
        'returns 200 no update available '
        'when unable to get latest version', () async {
      const payload = CheckForUpdatesRequest(
        version: '1.0.0',
        platform: 'android',
        arch: 'arm64',
        clientId: 'client-id',
      );

      when(
        () => store.latestVersionForClient(
          any(),
          currentVersion: any(named: 'currentVersion'),
        ),
      ).thenReturn(null);

      final request = Request(
        'POST',
        uri,
        body: json.encode(payload.toJson()),
      ).provide(() => store);

      final response = await checkForUpdatesHandler(request);

      expect(response.statusCode, HttpStatus.ok);

      final body = await response.readAsString();
      expect(body, equals('{"update_available":false}'));
    });

    test('returns 200 update available when version is not latest', () async {
      const payload = CheckForUpdatesRequest(
        version: '1.0.0',
        platform: 'android',
        arch: 'arm64',
        clientId: 'client-id',
      );

      when(
        () => store.latestVersionForClient(
          any(),
          currentVersion: any(named: 'currentVersion'),
        ),
      ).thenReturn('1.0.1');

      final request = Request(
        'POST',
        uri,
        body: json.encode(payload.toJson()),
      ).provide(() => store);

      final response = await checkForUpdatesHandler(request);

      expect(response.statusCode, HttpStatus.ok);

      final body = await response.readAsString();
      expect(
        body,
        equals(
          '{"update_available":true,"update":{"version":"1.0.1","hash":"","download_url":"https://shorebird-code-push-api-cypqazu4da-uc.a.run.app/api/v1/releases/1.0.1.txt"}}',
        ),
      );
    });
  });
}
