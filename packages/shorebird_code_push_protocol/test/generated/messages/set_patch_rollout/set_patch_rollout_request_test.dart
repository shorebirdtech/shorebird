// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SetPatchRolloutRequest', () {
    test(
      'SetPatchRolloutPercentageRequest round-trips via maybeFromJson/toJson',
      () {
        const instance = SetPatchRolloutPercentageRequest(rolloutPercentage: 0);
        final parsed = SetPatchRolloutPercentageRequest.maybeFromJson(
          instance.toJson(),
        )!;
        expect(parsed, equals(instance));
        expect(parsed.hashCode, equals(instance.hashCode));
      },
    );

    test(
      'SetPatchRolloutScheduleRequest round-trips via maybeFromJson/toJson',
      () {
        const instance = SetPatchRolloutScheduleRequest(
          rolloutSteps: <RolloutStep>[RolloutStep(percentage: 0)],
        );
        final parsed = SetPatchRolloutScheduleRequest.maybeFromJson(
          instance.toJson(),
        )!;
        expect(parsed, equals(instance));
        expect(parsed.hashCode, equals(instance.hashCode));
      },
    );

    test('maybeFromJson returns null on null input', () {
      expect(SetPatchRolloutRequest.maybeFromJson(null), isNull);
    });
  });
}
