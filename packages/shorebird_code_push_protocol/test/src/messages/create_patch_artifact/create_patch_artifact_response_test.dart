import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchArtifactResponse, () {
    test('can be (de)serialized', () {
      const request = CreatePatchArtifactResponse(
        id: 42,
        patchId: 1,
        arch: 'arm64',
        platform: ReleasePlatform.android,
        hash: '1234',
        size: 9876,
        url: 'https://example.com',
      );
      expect(
        CreatePatchArtifactResponse.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('can be (de)serialized with a resumable upload method', () {
      const response = CreatePatchArtifactResponse(
        id: 42,
        patchId: 1,
        arch: 'arm64',
        platform: ReleasePlatform.android,
        hash: '1234',
        size: 9876,
        url: 'https://example.com',
        uploadMethod: ArtifactUploadMethod.resumable,
      );
      final decoded = CreatePatchArtifactResponse.fromJson(response.toJson());
      expect(decoded.toJson(), equals(response.toJson()));
      expect(decoded.uploadMethod, equals(ArtifactUploadMethod.resumable));
    });
  });
}
