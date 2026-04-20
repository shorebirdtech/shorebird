// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('OrganizationMembership', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = OrganizationMembership(
        organization: Organization(
          id: 0,
          name: 'example',
          organizationType: OrganizationType.values.first,
          createdAt: DateTime.utc(2024),
          updatedAt: DateTime.utc(2024),
        ),
        role: Role.values.first,
      );
      final parsed = OrganizationMembership.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(OrganizationMembership.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => OrganizationMembership.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
