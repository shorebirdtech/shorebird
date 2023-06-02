import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateReleaseArtifactResponse, () {
    test('can be (de)serialized', () {
      const response = CreateReleaseArtifactResponse(
        id: 42,
        releaseId: 1,
        arch: 'arm64',
        platform: 'android',
        hash: '1234',
        size: 9876,
        uploadUrl: 'https://example.com',
      );
      expect(
        CreateReleaseArtifactResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
