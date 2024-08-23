import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(UpdateReleaseRequest, () {
    test('can be (de)serialized', () {
      final request = UpdateReleaseRequest(
        platform: ReleasePlatform.android,
        status: ReleaseStatus.active,
        metadata: const UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.ios,
          flutterVersionOverride: null,
          environment: BuildEnvironmentMetadata(
            flutterRevision: '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
            operatingSystem: 'macos',
            operatingSystemVersion: '11.1',
            shorebirdVersion: '1.2.3',
            xcodeVersion: '15.3',
          ),
        ).toJson(),
      );
      expect(
        UpdateReleaseRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('can be (de)serialized without metadata', () {
      const request = UpdateReleaseRequest(
        platform: ReleasePlatform.ios,
        status: ReleaseStatus.active,
        metadata: null,
      );
      expect(
        UpdateReleaseRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
