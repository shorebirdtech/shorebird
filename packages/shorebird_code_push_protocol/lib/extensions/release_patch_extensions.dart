import 'package:shorebird_code_push_protocol/src/models/patch_artifact.dart';
import 'package:shorebird_code_push_protocol/src/models/release_patch.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_step.dart';

/// Application-level behavior on [ReleasePatch] that does not fit in the
/// OpenAPI schema.
extension ReleasePatchExtensions on ReleasePatch {
  /// Returns a copy of this [ReleasePatch] with the given fields replaced by
  /// the new values.
  ReleasePatch copyWith({
    int? id,
    int? number,
    String? channel,
    List<PatchArtifact>? artifacts,
    bool? isRolledBack,
    DateTime? createdAt,
    double? rolloutPercentage,
    List<RolloutStep>? rolloutSteps,
    DateTime? rolloutNextStepAt,
    bool? rolloutPauseWeekends,
    String? rolloutTimezone,
    String? notes,
  }) => ReleasePatch(
    id: id ?? this.id,
    number: number ?? this.number,
    channel: channel ?? this.channel,
    artifacts: artifacts ?? this.artifacts,
    isRolledBack: isRolledBack ?? this.isRolledBack,
    createdAt: createdAt ?? this.createdAt,
    rolloutPercentage: rolloutPercentage ?? this.rolloutPercentage,
    rolloutSteps: rolloutSteps ?? this.rolloutSteps,
    rolloutNextStepAt: rolloutNextStepAt ?? this.rolloutNextStepAt,
    rolloutPauseWeekends: rolloutPauseWeekends ?? this.rolloutPauseWeekends,
    rolloutTimezone: rolloutTimezone ?? this.rolloutTimezone,
    notes: notes ?? this.notes,
  );

  /// Returns a copy of this [ReleasePatch] carrying exactly the given rollout
  /// schedule, including when the arguments are null.
  ///
  /// [copyWith] cannot clear a field, so a caller reporting a rollout it just
  /// replaced would inherit the schedule the replaced rollout was on.
  ReleasePatch withRolloutSchedule({
    required List<RolloutStep>? steps,
    required DateTime? nextStepAt,
    required bool? pauseWeekends,
    required String? timezone,
  }) => ReleasePatch(
    id: id,
    number: number,
    channel: channel,
    artifacts: artifacts,
    isRolledBack: isRolledBack,
    createdAt: createdAt,
    rolloutPercentage: rolloutPercentage,
    rolloutSteps: steps,
    rolloutNextStepAt: nextStepAt,
    rolloutPauseWeekends: pauseWeekends,
    rolloutTimezone: timezone,
    notes: notes,
  );
}
