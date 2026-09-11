import 'package:shorebird_cli/src/formatters/patch_formatter.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('formatPatchDetails', () {
    PatchArtifact artifact({
      required String arch,
      required ReleasePlatform platform,
      required int size,
    }) => PatchArtifact(
      id: 1,
      patchId: 0,
      arch: arch,
      platform: platform,
      hash: 'hash',
      size: size,
      createdAt: DateTime(2024),
    );

    test('omits track, notes, and artifacts when absent', () {
      expect(
        formatPatchDetails(
          const ReleasePatch(
            id: 42,
            number: 1,
            isRolledBack: false,
            artifacts: [],
          ),
        ),
        equals(['ID:          42', 'Number:      1', 'Rolled back: no']),
      );
    });

    test('includes every field when present', () {
      expect(
        formatPatchDetails(
          ReleasePatch(
            id: 42,
            number: 1,
            channel: 'stable',
            isRolledBack: true,
            notes: 'Optional patch notes.',
            artifacts: [
              artifact(
                arch: 'arm64-v8a',
                platform: ReleasePlatform.android,
                size: 1258291,
              ),
              artifact(
                arch: 'arm64',
                platform: ReleasePlatform.ios,
                size: 917504,
              ),
            ],
          ),
        ),
        equals([
          'ID:          42',
          'Number:      1',
          'Track:       stable',
          'Rolled back: yes',
          'Notes:       Optional patch notes.',
          'Artifacts:',
          '  android  arm64-v8a    1.20 MB',
          '  ios      arm64        896 KB',
        ]),
      );
    });
  });
}
