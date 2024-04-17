import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateReleaseArtifactRequest, () {
    test('can be (de)serialized', () {
      const request = CreateReleaseArtifactRequest(
        arch: 'arm64',
        platform: ReleasePlatform.android,
        hash: '1234',
        size: 9876,
        canSideload: true,
        filename: 'test.apk',
      );
      expect(
        CreateReleaseArtifactRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
