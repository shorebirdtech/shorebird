import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetReleaseResponse, () {
    test('can be (de)serialized', () {
      final response = GetReleaseResponse(
        release: Release(
          id: 0,
          appId: 'test-app-id',
          version: '1.0.0',
          flutterRevision: 'flutter-revision',
          flutterVersion: '3.22.0',
          displayName: 'v1.0.0',
          platformStatuses: const {
            ReleasePlatform.ios: ReleaseStatus.draft,
            ReleasePlatform.android: ReleaseStatus.active,
          },
          createdAt: DateTime(2022),
          updatedAt: DateTime(2023),
        ),
      );
      expect(
        GetReleaseResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
