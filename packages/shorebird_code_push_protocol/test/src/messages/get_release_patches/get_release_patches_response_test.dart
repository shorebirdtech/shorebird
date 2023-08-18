import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetReleasePatchesResponse, () {
    test('can be (de)serialized', () {
      const response = GetReleasePatchesResponse(
        patches: {
          1: [
            PatchArtifact(
              id: 1,
              patchId: 1,
              arch: 'aarch64',
              platform: ReleasePlatform.android,
              url: 'https://example.com',
              size: 42,
              hash: 'sha256:1234567890',
            ),
            PatchArtifact(
              id: 2,
              patchId: 1,
              arch: 'aarch64',
              platform: ReleasePlatform.android,
              url: 'https://example.com',
              size: 42,
              hash: 'sha256:1234567890',
            ),
          ],
          2: [
            PatchArtifact(
              id: 3,
              patchId: 2,
              arch: 'aarch64',
              platform: ReleasePlatform.android,
              url: 'https://example.com',
              size: 42,
              hash: 'sha256:1234567890',
            ),
            PatchArtifact(
              id: 4,
              patchId: 3,
              arch: 'aarch64',
              platform: ReleasePlatform.android,
              url: 'https://example.com',
              size: 42,
              hash: 'sha256:1234567890',
            ),
          ],
        },
      );
      expect(
        GetReleasePatchesResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
