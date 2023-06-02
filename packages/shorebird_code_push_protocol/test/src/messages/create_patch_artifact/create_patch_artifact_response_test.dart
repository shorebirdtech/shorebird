import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchArtifactResponse, () {
    test('can be (de)serialized', () {
      const request = CreatePatchArtifactResponse(
        arch: 'arm64',
        platform: 'android',
        hash: '1234',
        size: 9876,
        uploadUrl: 'https://example.com',
      );
      expect(
        CreatePatchArtifactResponse.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
