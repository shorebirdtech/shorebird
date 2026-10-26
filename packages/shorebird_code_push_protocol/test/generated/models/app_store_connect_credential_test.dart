// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AppStoreConnectCredential', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = AppStoreConnectCredential(
        id: 0,
        organizationId: 0,
        issuerId: '00000000-0000-0000-0000-000000000000',
        keyId: 'example',
        uploadedByUserId: 0,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      final parsed = AppStoreConnectCredential.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AppStoreConnectCredential.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AppStoreConnectCredential.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
