import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleaseArtifact, () {
    test('can be (de)serialized', () {
      const artifact = ReleaseArtifact(
        id: 1,
        releaseId: 1,
        arch: 'aarch64',
        platform: ReleasePlatform.android,
        url: 'https://example.com',
        size: 42,
        hash: 'sha256:1234567890',
        podfileLockHash: 'podfile-lock-hash',
        packageResolvedHash: 'package-resolved-hash',
        canSideload: true,
      );
      expect(
        ReleaseArtifact.fromJson(artifact.toJson()).toJson(),
        equals(artifact.toJson()),
      );
    });

    test('parses a response without package_resolved_hash', () {
      const artifact = ReleaseArtifact(
        id: 1,
        releaseId: 1,
        arch: 'aarch64',
        platform: ReleasePlatform.ios,
        url: 'https://example.com',
        size: 42,
        hash: 'sha256:1234567890',
        podfileLockHash: 'podfile-lock-hash',
        canSideload: true,
      );
      final json = artifact.toJson();
      expect(json.containsKey('package_resolved_hash'), isFalse);
      expect(ReleaseArtifact.fromJson(json).packageResolvedHash, isNull);
    });

    // Intentionally removed: the handwritten ReleaseArtifact overrode
    // toString to return the JSON-encoded body. The generated class does
    // not, which matches Dart defaults for data classes. Callers that
    // want a JSON string should call `artifact.toJson().toString()`.
  });
}
