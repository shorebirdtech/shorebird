// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetOrganizationUsersResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetOrganizationUsersResponse(
        users: <OrganizationUser>[
          OrganizationUser(
            user: PublicUser(id: 0, email: 'user@example.com'),
            role: Role.owner,
          ),
        ],
      );
      final parsed = GetOrganizationUsersResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetOrganizationUsersResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetOrganizationUsersResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
