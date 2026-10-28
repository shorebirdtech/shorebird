// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseServiceAccount', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = EnterpriseServiceAccount(
        userId: 0,
        name: 'example',
        teamId: 0,
        role: Role.owner,
        createdAt: DateTime.utc(2024),
        lastAuthAt: DateTime.utc(2024),
        createdByEmail: 'example',
      );
      final parsed = EnterpriseServiceAccount.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseServiceAccount.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseServiceAccount.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
