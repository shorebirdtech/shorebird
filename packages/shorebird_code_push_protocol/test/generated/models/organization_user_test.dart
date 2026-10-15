// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('OrganizationUser', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = OrganizationUser(
        user: PublicUser(id: 0, email: 'user@example.com'),
        role: Role.owner,
      );
      final parsed = OrganizationUser.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(OrganizationUser.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => OrganizationUser.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
