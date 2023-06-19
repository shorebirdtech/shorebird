import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleaseArtifact, () {
    test('can be (de)serialized', () {
      const artifact = ReleaseArtifact(
        id: 1,
        releaseId: 1,
        arch: 'aarch64',
        platform: 'android',
        url: 'https://example.com',
        size: 42,
        hash: 'sha256:1234567890',
      );
      expect(
        ReleaseArtifact.fromJson(artifact.toJson()).toJson(),
        equals(artifact.toJson()),
      );
    });

    test('toString prints a json representation of the object', () {
      const artifact = ReleaseArtifact(
        id: 1,
        releaseId: 1,
        arch: 'aarch64',
        platform: 'android',
        url: 'https://example.com',
        size: 42,
        hash: 'sha256:1234567890',
      );
      final artifactString = artifact.toString();
      expect(
        artifactString,
        '{id: 1, release_id: 1, arch: aarch64, platform: android, hash: sha256:1234567890, size: 42, url: https://example.com}',
      );
    });
  });
}
