import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetOrganizationUsersResponse, () {
    test('can be (de)serialized', () {
      final getOrganizationUsersRequest = GetOrganizationUsersResponse(
        users: [
          OrganizationUser(
            user: PublicUser.fromPrivateUser(PrivateUser.forTest()),
            role: OrganizationRole.owner,
          ),
        ],
      );
      expect(
        GetOrganizationUsersResponse.fromJson(
                getOrganizationUsersRequest.toJson())
            .toJson(),
        equals(getOrganizationUsersRequest.toJson()),
      );
    });
  });
}
