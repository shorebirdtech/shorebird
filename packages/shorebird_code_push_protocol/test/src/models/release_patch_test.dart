import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleasePatch, () {
    test('is equatable', () {
      expect(
        // Ignoring const constructor for equality comparison.
        const ReleasePatch(
          id: 0,
          number: 1,
          channel: 'channel',
          isRolledBack: false,
          artifacts: [],
        ),
        equals(
          // Ignoring const constructor for equality comparison.
          const ReleasePatch(
            id: 0,
            number: 1,
            channel: 'channel',
            isRolledBack: false,
            artifacts: [],
          ),
        ),
      );
    });

    group('copyWith', () {
      const patch = ReleasePatch(
        id: 0,
        number: 1,
        channel: 'channel',
        isRolledBack: false,
        artifacts: [],
        notes: 'notes',
      );

      test('returns an identical copy when no fields are provided', () {
        expect(patch.copyWith(), equals(patch));
      });

      test('replaces only the provided fields', () {
        final copy = patch.copyWith(isRolledBack: true);
        expect(copy.isRolledBack, isTrue);
        expect(copy.id, equals(patch.id));
        expect(copy.number, equals(patch.number));
        expect(copy.channel, equals(patch.channel));
        expect(copy.artifacts, equals(patch.artifacts));
        expect(copy.notes, equals(patch.notes));
      });

      test('replaces every field when all are provided', () {
        final artifact = PatchArtifact(
          id: 1,
          patchId: 0,
          arch: 'arm64',
          platform: ReleasePlatform.android,
          hash: 'hash',
          size: 42,
          createdAt: DateTime(2024),
        );
        final copy = patch.copyWith(
          id: 9,
          number: 2,
          channel: 'other-channel',
          artifacts: [artifact],
          isRolledBack: true,
          notes: 'other-notes',
        );
        expect(
          copy,
          equals(
            ReleasePatch(
              id: 9,
              number: 2,
              channel: 'other-channel',
              artifacts: [artifact],
              isRolledBack: true,
              notes: 'other-notes',
            ),
          ),
        );
      });
    });
  });
}
