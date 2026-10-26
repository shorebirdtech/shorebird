// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateServiceAccountKeyResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = CreateServiceAccountKeyResponse(
        apiKey: 'example',
        id: 0,
        name: 'example',
        createdAt: DateTime.utc(2024),
        lastUsedAt: DateTime.utc(2024),
        expiresAt: DateTime.utc(2024),
        scopes: const <String>['example'],
      );
      final parsed = CreateServiceAccountKeyResponse.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateServiceAccountKeyResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () =>
            CreateServiceAccountKeyResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
