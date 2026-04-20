// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Organization', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = Organization(
        id: 0,
        name: 'example',
        organizationType: OrganizationType.values.first,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      final parsed = Organization.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(Organization.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => Organization.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
