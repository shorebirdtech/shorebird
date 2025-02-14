import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetOrganizationsResponse, () {
    test('can be (de)serialized', () {
      final getOrganizationsResponse = GetOrganizationsResponse(
        organizations: [
          OrganizationMembership(
            organization: Organization.forTest(),
            role: OrganizationRole.member,
          ),
        ],
      );
      expect(
        GetOrganizationsResponse.fromJson(
          getOrganizationsResponse.toJson(),
        ).toJson(),
        equals(getOrganizationsResponse.toJson()),
      );
    });
  });
}
