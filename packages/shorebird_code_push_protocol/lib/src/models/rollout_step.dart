import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template rollout_step}
/// A step in a timed rollout schedule on a channel.
/// {@endtemplate}
@immutable
class RolloutStep {
  /// {@macro rollout_step}
  const RolloutStep({
    required this.percentage,
    this.durationMinutes,
  });

  /// Converts a `Map<String, dynamic>` to a [RolloutStep].
  factory RolloutStep.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'RolloutStep',
      json,
      () => RolloutStep(
        percentage: (json['percentage'] as num).toDouble(),
        durationMinutes: json['duration_minutes'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static RolloutStep? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return RolloutStep.fromJson(json);
  }

  /// The percentage of the channel's devices to offer the patch to at
  /// this step, a multiple of 0.01 from 0.01 to 100.
  final double percentage;

  /// How many minutes to hold at `percentage` before advancing to the
  /// next step. Absent on the final 100% step.
  final int? durationMinutes;

  /// Converts a [RolloutStep] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'percentage': percentage,
      'duration_minutes': ?durationMinutes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    percentage,
    durationMinutes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RolloutStep &&
        percentage == other.percentage &&
        durationMinutes == other.durationMinutes;
  }
}
