import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleasePatch, () {
    test('round-trips hiddenAt', () {
      final patch = ReleasePatch(
        id: 0,
        number: 1,
        isRolledBack: false,
        artifacts: const [],
        hiddenAt: DateTime.utc(2026, 10, 18),
      );
      expect(patch.toJson()['hidden_at'], equals('2026-10-18T00:00:00.000Z'));
      expect(ReleasePatch.fromJson(patch.toJson()), equals(patch));
    });

    test('parses a payload without hidden_at', () {
      final patch = ReleasePatch.fromJson(const {
        'id': 0,
        'number': 1,
        'artifacts': <Object>[],
        'is_rolled_back': false,
      });
      expect(patch.hiddenAt, isNull);
    });

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
        expect(copy.hiddenAt, equals(patch.hiddenAt));
      });

      test('keeps hiddenAt when other fields are replaced', () {
        final hiddenAt = DateTime.utc(2026, 10, 1);
        final copy = patch
            .copyWith(hiddenAt: hiddenAt)
            .copyWith(isRolledBack: true);
        expect(copy.hiddenAt, equals(hiddenAt));
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
          hiddenAt: DateTime.utc(2026, 10, 18),
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
              hiddenAt: DateTime.utc(2026, 10, 18),
            ),
          ),
        );
      });
    });
  });
}
