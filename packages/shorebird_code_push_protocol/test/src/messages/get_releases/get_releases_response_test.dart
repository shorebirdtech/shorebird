import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetReleasesResponse, () {
    test('can be (de)serialized', () {
      final response = GetReleasesResponse(
        releases: [
          Release(
            id: 0,
            displayName: 'v1.0.0',
            appId: 'test-app-id',
            flutterRevision: 'flutter-revision',
            version: '1.0.0',
            platformStatuses: {
              ReleasePlatform.ios: ReleaseStatus.draft,
              ReleasePlatform.android: ReleaseStatus.active,
            },
            createdAt: DateTime(2022),
            updatedAt: DateTime(2023),
          ),
        ],
      );
      expect(
        GetReleasesResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
