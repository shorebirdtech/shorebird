import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetOrganizationAppsResponse, () {
    test('can be (de)serialized', () {
      final getOrganizationAppsRequest = GetOrganizationAppsResponse(
        apps: [
          AppMetadata(
            appId: 'app-id',
            displayName: 'My app',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      );
      expect(
        GetOrganizationAppsResponse.fromJson(
          getOrganizationAppsRequest.toJson(),
        ).toJson(),
        equals(getOrganizationAppsRequest.toJson()),
      );
    });
  });
}
