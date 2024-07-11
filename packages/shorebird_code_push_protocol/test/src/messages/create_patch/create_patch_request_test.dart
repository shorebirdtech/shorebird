import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchRequest, () {
    test('can be (de)serialized', () {
      final request = CreatePatchRequest(
        releaseId: 1234,
        wasForced: true,
        metadata: const CreatePatchMetadata(
          releasePlatform: ReleasePlatform.android,
          usedIgnoreAssetChangesFlag: true,
          usedIgnoreNativeChangesFlag: false,
          hasAssetChanges: true,
          hasNativeChanges: false,
          linkPercentage: 99.9,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'linux',
            operatingSystemVersion: '1.0.0',
            shorebirdVersion: '1.2.3',
            xcodeVersion: null,
          ),
        ).toJson(),
      );
      expect(
        CreatePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('can be (de)serialized without metadata', () {
      final request = CreatePatchRequest(
        releaseId: 1234,
        wasForced: true,
        metadata: CreatePatchMetadata.forTest().toJson(),
      );
      expect(
        CreatePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
