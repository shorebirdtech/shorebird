import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ArtifactUploadUrls, () {
    test('can be (de)serialized', () {
      const artifactUploadUrls = ArtifactUploadUrls(
        android: AndroidArtifactUploadUrls(
          x86: 'x86',
          aarch64: 'aarch64',
          arm: 'arm',
        ),
      );
      expect(
        ArtifactUploadUrls.fromJson(artifactUploadUrls.toJson()).toJson(),
        equals(artifactUploadUrls.toJson()),
      );
    });
  });
}
