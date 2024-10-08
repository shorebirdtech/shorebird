import 'package:shorebird_cli/src/extensions/organization.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('OrganizationDisplay', () {
    group('displayName', () {
      test('should return the name for a team organization', () {
        final organization = Organization.forTest(
          organizationType: OrganizationType.team,
          name: 'My Organization',
        );
        expect(
          organization.displayName(user: PrivateUser.forTest()),
          equals('My Organization'),
        );
      });

      group('for a personal organization', () {
        group('when the user has a display name', () {
          final user = PrivateUser.forTest(displayName: 'John Doe');

          test("should return the user's display name", () {
            final organization = Organization.forTest();
            expect(organization.displayName(user: user), 'John Doe');
          });
        });

        group('when the user does not have a display name', () {
          final user = PrivateUser.forTest(email: 'test@test.com');

          test("should return the user's email", () {
            final organization = Organization.forTest();
            expect(
              organization.displayName(user: user),
              equals('test@test.com'),
            );
          });
        });
      });
    });
  });
}
