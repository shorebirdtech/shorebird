import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(Release, () {
    test('can be (de)serialized', () {
      const release = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        displayName: 'v1.0.0',
        platformStatuses: {ReleasePlatform.android: ReleaseStatus.active},
      );
      expect(
        Release.fromJson(release.toJson()).toJson(),
        equals(release.toJson()),
      );
    });
  });
}
