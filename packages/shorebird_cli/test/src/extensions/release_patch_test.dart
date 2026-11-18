import 'package:shorebird_cli/src/extensions/release_patch.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group('ReleasePatchPlatform', () {
    PatchArtifact artifact(ReleasePlatform platform) => PatchArtifact(
      id: 1,
      patchId: 1,
      arch: 'aarch64',
      platform: platform,
      hash: '#',
      size: 1,
      createdAt: DateTime(2023),
    );

    test('prefers the platform the server recorded', () {
      final patch = ReleasePatch(
        id: 1,
        number: 1,
        artifacts: [artifact(ReleasePlatform.android)],
        isRolledBack: false,
        platform: ReleasePlatform.ios,
      );
      expect(patch.resolvedPlatform, equals(ReleasePlatform.ios));
    });

    test("falls back to the artifacts' platform", () {
      final patch = ReleasePatch(
        id: 1,
        number: 1,
        artifacts: [artifact(ReleasePlatform.android)],
        isRolledBack: false,
      );
      expect(patch.resolvedPlatform, equals(ReleasePlatform.android));
    });

    test('is null when neither says', () {
      const patch = ReleasePatch(
        id: 1,
        number: 1,
        artifacts: [],
        isRolledBack: false,
      );
      expect(patch.resolvedPlatform, isNull);
    });
  });
}
