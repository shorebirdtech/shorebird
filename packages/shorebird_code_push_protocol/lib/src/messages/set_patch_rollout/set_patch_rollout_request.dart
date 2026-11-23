// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
// ignore_for_file: lines_longer_than_80_chars
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_step.dart';

/// The request body for PUT
/// /apps/{appId}/releases/{releaseId}/patches/{patchId}/rollout: either
/// a rollout percentage or a timed rollout schedule.
sealed class SetPatchRolloutRequest {
  const SetPatchRolloutRequest();

  factory SetPatchRolloutRequest.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('rollout_percentage')) {
      return SetPatchRolloutPercentageRequest.fromJson(json);
    }
    if (json.containsKey('rollout_steps')) {
      return SetPatchRolloutScheduleRequest.fromJson(json);
    }
    throw FormatException(
      'No variant of SetPatchRolloutRequest matched json keys: ${json.keys.toList()}',
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

  /// Require all subclasses to implement toJson.
  Map<String, dynamic> toJson();
}

/// {@template set_patch_rollout_percentage_request}
/// Sets a patch's rollout percentage.
/// {@endtemplate}
@immutable
final class SetPatchRolloutPercentageRequest extends SetPatchRolloutRequest {
  /// {@macro set_patch_rollout_percentage_request}
  const SetPatchRolloutPercentageRequest({
    required this.rolloutPercentage,
    this.platforms,
  });

  /// Converts a `Map<String, dynamic>` to a [SetPatchRolloutPercentageRequest].
  factory SetPatchRolloutPercentageRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'SetPatchRolloutPercentageRequest',
      json,
      () => SetPatchRolloutPercentageRequest(
        rolloutPercentage: (json['rollout_percentage'] as num).toDouble(),
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static SetPatchRolloutPercentageRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return SetPatchRolloutPercentageRequest.fromJson(json);
  }

  /// The percentage of the channel's devices to offer the patch to, a
  /// multiple of 0.01 from 0.01 to 100, no lower than the patch's
  /// current one. Setting the current percentage holds an active timed
  /// rollout schedule in place.
  final double rolloutPercentage;

  /// The platforms whose patches under the number to set the rollout
  /// of, at least one. Omit to set every platform's.
  /// Unstable: this may change shape until patch linking ships.
  final List<ReleasePlatform>? platforms;

  /// Converts a [SetPatchRolloutPercentageRequest] to a `Map<String, dynamic>`.
  @override
  Map<String, dynamic> toJson() {
    return {
      'rollout_percentage': rolloutPercentage,
      'platforms': ?platforms?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    rolloutPercentage,
    listHash(platforms),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SetPatchRolloutPercentageRequest &&
        rolloutPercentage == other.rolloutPercentage &&
        listsEqual(platforms, other.platforms);
  }
}

/// {@template set_patch_rollout_schedule_request}
/// Starts a timed rollout schedule for a patch.
/// {@endtemplate}
@immutable
final class SetPatchRolloutScheduleRequest extends SetPatchRolloutRequest {
  /// {@macro set_patch_rollout_schedule_request}
  const SetPatchRolloutScheduleRequest({
    required this.rolloutSteps,
    this.rolloutPauseWeekends,
    this.rolloutTimezone,
    this.platforms,
  });

  /// Converts a `Map<String, dynamic>` to a [SetPatchRolloutScheduleRequest].
  factory SetPatchRolloutScheduleRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'SetPatchRolloutScheduleRequest',
      json,
      () => SetPatchRolloutScheduleRequest(
        rolloutSteps: (json['rollout_steps'] as List)
            .map<RolloutStep>(
              (e) => RolloutStep.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        rolloutPauseWeekends: json['rollout_pause_weekends'] as bool?,
        rolloutTimezone: json['rollout_timezone'] as String?,
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static SetPatchRolloutScheduleRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return SetPatchRolloutScheduleRequest.fromJson(json);
  }

  /// A timed rollout schedule of 2 to 10 strictly increasing percentage
  /// steps ending at 100.
  final List<RolloutStep> rolloutSteps;

  /// Whether to pause step advancement over weekends in
  /// `rollout_timezone`.
  final bool? rolloutPauseWeekends;

  /// The IANA timezone name used to evaluate weekend pauses. Defaults
  /// to `UTC`.
  final String? rolloutTimezone;

  /// The platforms whose patches under the number to set the rollout
  /// of, at least one. Omit to set every platform's.
  /// Unstable: this may change shape until patch linking ships.
  final List<ReleasePlatform>? platforms;

  /// Converts a [SetPatchRolloutScheduleRequest] to a `Map<String, dynamic>`.
  @override
  Map<String, dynamic> toJson() {
    return {
      'rollout_steps': rolloutSteps.map((e) => e.toJson()).toList(),
      'rollout_pause_weekends': ?rolloutPauseWeekends,
      'rollout_timezone': ?rolloutTimezone,
      'platforms': ?platforms?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(rolloutSteps),
    rolloutPauseWeekends,
    rolloutTimezone,
    listHash(platforms),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SetPatchRolloutScheduleRequest &&
        listsEqual(rolloutSteps, other.rolloutSteps) &&
        rolloutPauseWeekends == other.rolloutPauseWeekends &&
        rolloutTimezone == other.rolloutTimezone &&
        listsEqual(platforms, other.platforms);
  }
}
