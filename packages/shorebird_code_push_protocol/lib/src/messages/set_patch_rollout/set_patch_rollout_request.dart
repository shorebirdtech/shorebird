import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_step.dart';

/// {@template set_patch_rollout_request}
/// The request body for PUT
/// /apps/{appId}/releases/{releaseId}/patches/{patchId}/rollout.
/// {@endtemplate}
@immutable
class SetPatchRolloutRequest {
  /// {@macro set_patch_rollout_request}
  const SetPatchRolloutRequest({
    this.rolloutPercentage,
    this.rolloutSteps,
    this.rolloutPauseWeekends,
    this.rolloutTimezone,
  });

  /// Converts a `Map<String, dynamic>` to a [SetPatchRolloutRequest].
  factory SetPatchRolloutRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'SetPatchRolloutRequest',
      json,
      () => SetPatchRolloutRequest(
        rolloutPercentage: (json['rollout_percentage'] as num?)?.toDouble(),
        rolloutSteps: (json['rollout_steps'] as List?)
            ?.map<RolloutStep>(
              (e) => RolloutStep.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        rolloutPauseWeekends: json['rollout_pause_weekends'] as bool?,
        rolloutTimezone: json['rollout_timezone'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static SetPatchRolloutRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return SetPatchRolloutRequest.fromJson(json);
  }

  /// The percentage of the channel's devices to offer the patch to, a
  /// multiple of 0.01 from 0.01 to 100, no lower than the patch's
  /// current one. Mutually exclusive with `rollout_steps`.
  final double? rolloutPercentage;

  /// A timed rollout schedule of 2 to 10 strictly increasing percentage
  /// steps ending at 100. Mutually exclusive with `rollout_percentage`.
  final List<RolloutStep>? rolloutSteps;

  /// Whether to pause step advancement over weekends in
  /// `rollout_timezone`.
  final bool? rolloutPauseWeekends;

  /// The IANA timezone name used to evaluate weekend pauses. Defaults
  /// to `UTC`.
  final String? rolloutTimezone;

  /// Converts a [SetPatchRolloutRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'rollout_percentage': ?rolloutPercentage,
      'rollout_steps': ?rolloutSteps?.map((e) => e.toJson()).toList(),
      'rollout_pause_weekends': ?rolloutPauseWeekends,
      'rollout_timezone': ?rolloutTimezone,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    rolloutPercentage,
    listHash(rolloutSteps),
    rolloutPauseWeekends,
    rolloutTimezone,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SetPatchRolloutRequest &&
        rolloutPercentage == other.rolloutPercentage &&
        listsEqual(rolloutSteps, other.rolloutSteps) &&
        rolloutPauseWeekends == other.rolloutPauseWeekends &&
        rolloutTimezone == other.rolloutTimezone;
  }
}
