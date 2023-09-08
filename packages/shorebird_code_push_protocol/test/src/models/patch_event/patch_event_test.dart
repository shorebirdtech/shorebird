import 'package:shorebird_code_push_protocol/src/models/models.dart';
import 'package:test/test.dart';

void main() {
  group(PatchEvent, () {
    group(PatchEvent, () {
      test('can be (de)serialized', () {
        const event = PatchEvent(
          clientId: 'some-client-id',
          appId: 'some-app-id',
          patchNumber: 2,
          arch: 'arm64',
          platform: ReleasePlatform.android,
          releaseVersion: '1.0.0',
          identifier: '__patch_install__',
        );
        expect(
          event.toJson(),
          equals(
            PatchEvent.fromJson(event.toJson()).toJson(),
          ),
        );
      });
    });
  });
}
