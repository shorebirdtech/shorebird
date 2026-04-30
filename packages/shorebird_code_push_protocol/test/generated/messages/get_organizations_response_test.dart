// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetOrganizationsResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetOrganizationsResponse(
        organizations: <OrganizationMembership>[
          OrganizationMembership(
            organization: Organization(
              id: 0,
              name: 'example',
              organizationType: OrganizationType.values.first,
              createdAt: DateTime.utc(2024),
              updatedAt: DateTime.utc(2024),
            ),
            role: Role.values.first,
          ),
        ],
      );
      final parsed = GetOrganizationsResponse.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetOrganizationsResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetOrganizationsResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
