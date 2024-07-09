import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetReleasePatchesResponse, () {
    test('can be (de)serialized', () {
      final response = GetReleasePatchesResponse(
        patches: [
          ReleasePatch(
            id: 42,
            number: 1,
            channel: 'stable',
            artifacts: [
              PatchArtifact(
                id: 1,
                patchId: 1,
                arch: 'aarch64',
                platform: ReleasePlatform.android,
                size: 42,
                hash: 'sha256:1234567890',
                createdAt: DateTime(2023),
              ),
              PatchArtifact(
                id: 2,
                patchId: 1,
                arch: 'aarch64',
                platform: ReleasePlatform.android,
                size: 42,
                hash: 'sha256:1234567890',
                createdAt: DateTime(2023),
              ),
            ],
          ),
          ReleasePatch(
            id: 43,
            number: 2,
            channel: null,
            artifacts: [
              PatchArtifact(
                id: 3,
                patchId: 2,
                arch: 'aarch64',
                platform: ReleasePlatform.android,
                size: 42,
                hash: 'sha256:1234567890',
                createdAt: DateTime(2023),
              ),
              PatchArtifact(
                id: 4,
                patchId: 3,
                arch: 'aarch64',
                platform: ReleasePlatform.android,
                size: 42,
                hash: 'sha256:1234567890',
                createdAt: DateTime(2023),
              ),
            ],
          ),
        ],
      );
      expect(
        GetReleasePatchesResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });

  group(ReleasePatch, () {
    test('is equatable', () {
      expect(
        const ReleasePatch(
          id: 0,
          number: 1,
          channel: 'channel',
          artifacts: [],
        ),
        equals(
          const ReleasePatch(
            id: 0,
            number: 1,
            channel: 'channel',
            artifacts: [],
          ),
        ),
      );
    });
  });
}
