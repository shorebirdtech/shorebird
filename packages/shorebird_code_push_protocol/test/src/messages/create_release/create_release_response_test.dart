import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateReleaseResponse, () {
    test('can be (de)serialized', () {
      const response = CreateReleaseResponse(
        release: Release(
          id: 0,
          appId: 'test-app-id',
          version: '1.0.0',
          displayName: 'v1.0.0',
          flutterRevision: 'flutter-revision',
        ),
        artifactUploadUrls: ArtifactUploadUrls(
          android: AndroidArtifactUploadUrls(
            x86: 'x86',
            aarch64: 'aarch64',
            arm: 'arm',
          ),
        ),
      );
      expect(
        CreateReleaseResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
