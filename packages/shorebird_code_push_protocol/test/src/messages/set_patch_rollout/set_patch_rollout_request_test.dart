import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(SetPatchRolloutRequest, () {
    test('can be (de)serialized with rolloutPercentage', () {
      const request = SetPatchRolloutRequest(rolloutPercentage: 25.5);
      final json = request.toJson();
      expect(json['rollout_percentage'], equals(25.5));
      expect(json, isNot(contains('rollout_steps')));
      expect(SetPatchRolloutRequest.fromJson(json), equals(request));
    });

    test('can be (de)serialized with a timed rollout schedule', () {
      const request = SetPatchRolloutRequest(
        rolloutSteps: [
          RolloutStep(percentage: 10, durationMinutes: 720),
          RolloutStep(percentage: 100),
        ],
        rolloutPauseWeekends: true,
        rolloutTimezone: 'America/New_York',
      );
      final json = request.toJson();
      expect(json, isNot(contains('rollout_percentage')));
      expect(
        json['rollout_steps'],
        equals([
          {'percentage': 10.0, 'duration_minutes': 720},
          {'percentage': 100.0},
        ]),
      );
      expect(json['rollout_pause_weekends'], isTrue);
      expect(json['rollout_timezone'], equals('America/New_York'));
      expect(SetPatchRolloutRequest.fromJson(json), equals(request));
    });
  });
}
