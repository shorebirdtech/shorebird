// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceAccount', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = ServiceAccount(
        id: 0,
        organizationId: 0,
        name: 'example',
        label: 'example',
        role: ServiceAccountRole.viewer,
        createdAt: DateTime.utc(2024),
        createdByUserId: 0,
        createdByEmail: 'example',
        lastAuthAt: DateTime.utc(2024),
      );
      final parsed = ServiceAccount.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ServiceAccount.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ServiceAccount.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
