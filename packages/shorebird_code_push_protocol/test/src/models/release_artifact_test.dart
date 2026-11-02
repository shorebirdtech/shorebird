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
        canSideload: true,
      );
      expect(
        ReleaseArtifact.fromJson(artifact.toJson()).toJson(),
        equals(artifact.toJson()),
      );
    });

    test('carries the signing its binary embeds', () {
      const artifact = ReleaseArtifact(
        id: 1,
        releaseId: 1,
        arch: 'aarch64',
        platform: ReleasePlatform.android,
        url: 'https://example.com',
        size: 42,
        hash: 'sha256:1234567890',
        canSideload: false,
        signing: ArtifactSigning(
          mode: 'managed',
          keyId: 7,
          publicKeyPem: 'pem',
        ),
      );
      final json = artifact.toJson();
      expect(json['signing'], {
        'mode': 'managed',
        'key_id': 7,
        'public_key_pem': 'pem',
      });
      final parsed = ReleaseArtifact.fromJson(json);
      expect(parsed.signing, artifact.signing);
      expect(parsed.signing!.signingMode, ReleaseSigningMode.managed);
    });

    test('reads a signing mode it does not know as unknown', () {
      final json = const ReleaseArtifact(
        id: 1,
        releaseId: 1,
        arch: 'aarch64',
        platform: ReleasePlatform.android,
        url: 'https://example.com',
        size: 42,
        hash: 'sha256:1234567890',
        canSideload: false,
      ).toJson()..['signing'] = {'mode': 'hardware'};
      final parsed = ReleaseArtifact.fromJson(json);
      expect(parsed.signing!.mode, 'hardware');
      expect(parsed.signing!.signingMode, isNull);
    });

    test('omits signing for an artifact uploaded before it', () {
      const artifact = ReleaseArtifact(
        id: 1,
        releaseId: 1,
        arch: 'aarch64',
        platform: ReleasePlatform.android,
        url: 'https://example.com',
        size: 42,
        hash: 'sha256:1234567890',
        canSideload: false,
      );
      expect(artifact.toJson().containsKey('signing'), isFalse);
      expect(ReleaseArtifact.fromJson(artifact.toJson()).signing, isNull);
    });

    // Intentionally removed: the handwritten ReleaseArtifact overrode
    // toString to return the JSON-encoded body. The generated class does
    // not, which matches Dart defaults for data classes. Callers that
    // want a JSON string should call `artifact.toJson().toString()`.
  });
}
