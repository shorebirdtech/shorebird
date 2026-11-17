import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_step.dart';

/// {@template promote_patch_request}
/// The request body for POST /apps/{appId}/patches/promote.
/// {@endtemplate}
@immutable
class PromotePatchRequest {
  /// {@macro promote_patch_request}
  const PromotePatchRequest({
    required this.patchId,
    required this.channelId,
    this.rolloutPercentage,
    this.rolloutSteps,
    this.rolloutPauseWeekends,
    this.rolloutTimezone,
  });

  /// Converts a `Map<String, dynamic>` to a [PromotePatchRequest].
  factory PromotePatchRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PromotePatchRequest',
      json,
      () => PromotePatchRequest(
        patchId: json['patch_id'] as int,
        channelId: json['channel_id'] as int,
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
  static PromotePatchRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PromotePatchRequest.fromJson(json);
  }

  /// The ID of the patch.
  final int patchId;

  /// The ID of the channel.
  final int channelId;

  /// The percentage of the channel's devices to offer the patch to, a
  /// multiple of 0.01 from 0.01 to 100. Defaults to 100.
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

  /// Converts a [PromotePatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'patch_id': patchId,
      'channel_id': channelId,
      'rollout_percentage': ?rolloutPercentage,
      'rollout_steps': ?rolloutSteps?.map((e) => e.toJson()).toList(),
      'rollout_pause_weekends': ?rolloutPauseWeekends,
      'rollout_timezone': ?rolloutTimezone,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    patchId,
    channelId,
    rolloutPercentage,
    listHash(rolloutSteps),
    rolloutPauseWeekends,
    rolloutTimezone,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PromotePatchRequest &&
        patchId == other.patchId &&
        channelId == other.channelId &&
        rolloutPercentage == other.rolloutPercentage &&
        listsEqual(rolloutSteps, other.rolloutSteps) &&
        rolloutPauseWeekends == other.rolloutPauseWeekends &&
        rolloutTimezone == other.rolloutTimezone;
  }
}
