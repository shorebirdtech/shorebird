// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RolloutSpeedSample', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = RolloutSpeedSample(
        artifactType: RolloutArtifactType.values.first,
        releaseVersion: 'example',
        patchNumber: 0,
        startedAt: DateTime.utc(2024),
        rungCrossings: <RolloutRungCrossing>[
          RolloutRungCrossing(rung: 0, crossedAt: DateTime.utc(2024)),
        ],
        eligible: false,
      );
      final parsed = RolloutSpeedSample.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RolloutSpeedSample.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => RolloutSpeedSample.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
