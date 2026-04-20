import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PatchCheckRequest, () {
    const request = PatchCheckRequest(
      releaseVersion: '1',
      patchNumber: 2,
      patchHash: '3',
      platform: ReleasePlatform.android,
      arch: 'arm64',
      appId: 'app_123',
      channel: 'channel_123',
      clientId: 'client_123',
      currentPatchNumber: 4,
    );

    test('can be (de)serialized', () {
      expect(
        PatchCheckRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('is equatable', () {
      const copy = PatchCheckRequest(
        releaseVersion: '1',
        patchNumber: 2,
        patchHash: '3',
        platform: ReleasePlatform.android,
        arch: 'arm64',
        appId: 'app_123',
        channel: 'channel_123',
        clientId: 'client_123',
        currentPatchNumber: 4,
      );
      const different = PatchCheckRequest(
        releaseVersion: '1',
        patchNumber: 2,
        patchHash: '3',
        platform: ReleasePlatform.android,
        arch: 'arm64',
        appId: 'app_123',
        channel: 'channel_123',
        clientId: 'client_123',
        currentPatchNumber: 5,
      );

      expect(request, equals(copy));
      expect(request, isNot(equals(different)));
    });
  });
}
