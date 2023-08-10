import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PatchInstallEvent, () {
    test('can be (de)serialized', () {
      final event = PatchInstallEvent(
        clientId: 'some-client-id',
        appId: 'some-app-id',
        patchNumber: 2,
        arch: 'arm64',
        platform: ReleasePlatform.android,
        releaseVersion: '1.0.0',
      );
      expect(
        PatchInstallEvent.fromJson(event.toJson()).toJson(),
        equals(event.toJson()),
      );
    });
  });
}
