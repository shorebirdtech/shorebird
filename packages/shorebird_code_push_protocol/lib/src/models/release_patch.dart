import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_artifact.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_step.dart';

/// {@template release_patch}
/// A patch for a given release.
/// {@endtemplate}
@immutable
class ReleasePatch {
  /// {@macro release_patch}
  const ReleasePatch({
    required this.id,
    required this.number,
    required this.artifacts,
    required this.isRolledBack,
    this.channel,
    this.createdAt,
    this.rolloutPercentage,
    this.rolloutSteps,
    this.rolloutNextStepAt,
    this.rolloutPauseWeekends,
    this.rolloutTimezone,
    this.notes,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleasePatch].
  factory ReleasePatch.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReleasePatch',
      json,
      () => ReleasePatch(
        id: json['id'] as int,
        number: json['number'] as int,
        channel: json['channel'] as String?,
        artifacts: (json['artifacts'] as List)
            .map<PatchArtifact>(
              (e) => PatchArtifact.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        isRolledBack: json['is_rolled_back'] as bool,
        createdAt: maybeParseDateTime(json['created_at'] as String?),
        rolloutPercentage: (json['rollout_percentage'] as num?)?.toDouble(),
        rolloutSteps: (json['rollout_steps'] as List?)
            ?.map<RolloutStep>(
              (e) => RolloutStep.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        rolloutNextStepAt: maybeParseDateTime(
          json['rollout_next_step_at'] as String?,
        ),
        rolloutPauseWeekends: json['rollout_pause_weekends'] as bool?,
        rolloutTimezone: json['rollout_timezone'] as String?,
        notes: json['notes'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReleasePatch? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReleasePatch.fromJson(json);
  }

  /// The patch id.
  final int id;

  /// The patch number.
  final int number;

  /// The channel associated with the patch.
  final String? channel;

  /// The associated patch artifacts.
  final List<PatchArtifact> artifacts;

  /// Whether the patch has been rolled back.
  final bool isRolledBack;

  /// The date and time the patch was created. Optional because it was
  /// added later; older servers do not send it.
  final DateTime? createdAt;

  /// The percentage of `channel`'s devices the patch is offered to.
  /// Absent when the patch is on no channel.
  final double? rolloutPercentage;

  /// The remaining steps of an in-progress timed rollout schedule on
  /// `channel`, starting with the active step. Absent when the rollout
  /// is fixed or the patch is on no channel.
  final List<RolloutStep>? rolloutSteps;

  /// When the next step in `rollout_steps` is scheduled to apply.
  /// Absent when `rollout_steps` is absent.
  final DateTime? rolloutNextStepAt;

  /// Whether the timed rollout schedule on `channel` pauses step
  /// advancement over weekends in `rollout_timezone`. Absent when the
  /// patch is on no channel.
  final bool? rolloutPauseWeekends;

  /// The IANA timezone name used to evaluate weekend pauses on
  /// `channel`. Absent when the patch is on no channel.
  final String? rolloutTimezone;

  /// Freeform notes associated with the patch, if any.
  final String? notes;

  /// Converts a [ReleasePatch] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'channel': ?channel,
      'artifacts': artifacts.map((e) => e.toJson()).toList(),
      'is_rolled_back': isRolledBack,
      'created_at': ?createdAt?.toUtc().toIso8601String(),
      'rollout_percentage': ?rolloutPercentage,
      'rollout_steps': ?rolloutSteps?.map((e) => e.toJson()).toList(),
      'rollout_next_step_at': ?rolloutNextStepAt?.toUtc().toIso8601String(),
      'rollout_pause_weekends': ?rolloutPauseWeekends,
      'rollout_timezone': ?rolloutTimezone,
      'notes': ?notes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    number,
    channel,
    listHash(artifacts),
    isRolledBack,
    createdAt,
    rolloutPercentage,
    listHash(rolloutSteps),
    rolloutNextStepAt,
    rolloutPauseWeekends,
    rolloutTimezone,
    notes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReleasePatch &&
        id == other.id &&
        number == other.number &&
        channel == other.channel &&
        listsEqual(artifacts, other.artifacts) &&
        isRolledBack == other.isRolledBack &&
        createdAt == other.createdAt &&
        rolloutPercentage == other.rolloutPercentage &&
        listsEqual(rolloutSteps, other.rolloutSteps) &&
        rolloutNextStepAt == other.rolloutNextStepAt &&
        rolloutPauseWeekends == other.rolloutPauseWeekends &&
        rolloutTimezone == other.rolloutTimezone &&
        notes == other.notes;
  }
}
