// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetRolloutSpeedResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetRolloutSpeedResponse(
        asOf: DateTime.utc(2024),
        lookbackDays: 0,
        rungs: const <double>[0],
        samples: <RolloutSpeedSample>[
          RolloutSpeedSample(
            artifactType: RolloutArtifactType.values.first,
            releaseVersion: 'example',
            patchNumber: 0,
            createdAt: DateTime.utc(2024),
            rungCrossings: <RolloutRungCrossing>[
              RolloutRungCrossing(rung: 0, crossedAt: DateTime.utc(2024)),
            ],
          ),
        ],
      );
      final parsed = GetRolloutSpeedResponse.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetRolloutSpeedResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetRolloutSpeedResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
