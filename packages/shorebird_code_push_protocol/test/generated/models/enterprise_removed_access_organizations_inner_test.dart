// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseRemovedAccessOrganizationsInner', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseRemovedAccessOrganizationsInner(
        organizationId: 0,
        organizationName: 'example',
        role: Role.owner,
      );
      final parsed = EnterpriseRemovedAccessOrganizationsInner.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(
        EnterpriseRemovedAccessOrganizationsInner.maybeFromJson(null),
        isNull,
      );
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseRemovedAccessOrganizationsInner.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
