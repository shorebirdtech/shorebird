// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetServiceAccountKeysResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetServiceAccountKeysResponse(
        keys: <ServiceAccountKey>[
          ServiceAccountKey(
            id: 0,
            name: 'example',
            createdAt: DateTime.utc(2024),
            lastUsedAt: DateTime.utc(2024),
            expiresAt: DateTime.utc(2024),
            scopes: const <String>['example'],
          ),
        ],
      );
      final parsed = GetServiceAccountKeysResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetServiceAccountKeysResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetServiceAccountKeysResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
