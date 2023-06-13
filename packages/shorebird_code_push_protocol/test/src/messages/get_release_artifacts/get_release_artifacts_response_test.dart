import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetReleaseArtifactsResponse, () {
    test('can be (de)serialized', () {
      const response = GetReleaseArtifactsResponse(
        artifacts: [
          ReleaseArtifact(
            id: 42,
            releaseId: 1,
            arch: 'aarch64',
            platform: 'android',
            hash: '#',
            size: 1337,
            url: 'https://example.com',
          ),
        ],
      );
      expect(
        GetReleaseArtifactsResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
