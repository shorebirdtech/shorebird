import 'package:shorebird_cli/src/auth/api_key.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ApiKeyScope, () {
    test('maps wire names back to scopes', () {
      expect(
        ApiKeyScope.fromWireName('release_and_patch'),
        equals(ApiKeyScope.releaseAndPatch),
      );
      expect(
        ApiKeyScope.fromWireName('full_access'),
        equals(ApiKeyScope.fullAccess),
      );
    });

    test('returns null for a scope this CLI does not know', () {
      expect(ApiKeyScope.fromWireName('something_new'), isNull);
    });

    test('flag names are the hyphenated form', () {
      expect(ApiKeyScope.releaseAndPatch.flagName, equals('release-and-patch'));
      expect(ApiKeyScope.fullAccess.flagName, equals('full-access'));
    });
  });

  group(ApiKeyMetadata, () {
    test('parses a full response', () {
      final key = ApiKeyMetadata.fromJson(const {
        'id': '7',
        'name': 'Production CI',
        'created_at': '2026-01-04T00:00:00.000Z',
        'last_used_at': '2026-09-06T00:00:00.000Z',
        'expires_at': '2027-01-04T00:00:00.000Z',
        'scope': 'release_and_patch',
      });

      expect(key.id, equals('7'));
      expect(key.name, equals('Production CI'));
      expect(key.createdAt, equals(DateTime.utc(2026, 1, 4)));
      expect(key.lastUsedAt, equals(DateTime.utc(2026, 9, 6)));
      expect(key.expiresAt, equals(DateTime.utc(2027, 1, 4)));
      expect(key.scope, equals(ApiKeyScope.releaseAndPatch));
    });

    test('tolerates null timestamps and a missing scope', () {
      final key = ApiKeyMetadata.fromJson(const {
        'id': '9',
        'name': 'Old key',
        'created_at': '2026-01-04T00:00:00.000Z',
        'last_used_at': null,
        'expires_at': null,
      });

      expect(key.lastUsedAt, isNull);
      expect(key.expiresAt, isNull);
      expect(key.scope, isNull);
    });

    test('reports an unrecognized scope as null rather than guessing', () {
      final key = ApiKeyMetadata.fromJson(const {
        'id': '9',
        'name': 'Future key',
        'created_at': '2026-01-04T00:00:00.000Z',
        'scope': 'invented_later',
      });

      expect(key.scope, isNull);
    });

    test('compares by value', () {
      final a = ApiKeyMetadata(
        id: '1',
        name: 'k',
        createdAt: DateTime.utc(2026),
      );
      final b = ApiKeyMetadata(
        id: '1',
        name: 'k',
        createdAt: DateTime.utc(2026),
      );
      expect(a, equals(b));
    });
  });

  group('exceptions', () {
    test('ApiKeyRequestException prints its message', () {
      expect(const ApiKeyRequestException('nope').toString(), equals('nope'));
    });

    test('ApiKeySessionRequiredException points at `shorebird login`', () {
      expect(
        const ApiKeySessionRequiredException().toString(),
        contains('shorebird login'),
      );
    });

    test('ApiKeyScopeMismatchException names both scopes', () {
      const exception = ApiKeyScopeMismatchException(
        requested: ApiKeyScope.releaseAndPatch,
        granted: ApiKeyScope.fullAccess,
      );
      expect(exception.toString(), contains('release-and-patch'));
      expect(exception.toString(), contains('full-access'));
    });

    test('ApiKeyScopeMismatchException handles an absent granted scope', () {
      const exception = ApiKeyScopeMismatchException(
        requested: ApiKeyScope.releaseAndPatch,
        granted: null,
      );
      expect(exception.toString(), contains('an unknown scope'));
    });
  });
}
