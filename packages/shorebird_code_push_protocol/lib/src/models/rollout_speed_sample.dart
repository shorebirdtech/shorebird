import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_artifact_type.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_ineligible_reason.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_rung_crossing.dart';

/// {@template rollout_speed_sample}
/// The rollout waypoints for one artifact — a store release or a patch.
/// All shares are fractions of the sample's *own* target audience: the
/// app's devices on the release's platform(s) for a release, the
/// distinct devices on the parent release for a patch. The two
/// audiences differ; consumers must never present the two sides'
/// percentages as the same population.
/// {@endtemplate}
@immutable
class RolloutSpeedSample {
  /// {@macro rollout_speed_sample}
  const RolloutSpeedSample({
    required this.artifactType,
    required this.releaseVersion,
    required this.patchNumber,
    required this.startedAt,
    required this.rungCrossings,
    required this.eligible,
    this.ineligibleReason,
  });

  /// Converts a `Map<String, dynamic>` to a [RolloutSpeedSample].
  factory RolloutSpeedSample.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'RolloutSpeedSample',
      json,
      () => RolloutSpeedSample(
        artifactType: RolloutArtifactType.fromJson(
          json['artifact_type'] as String,
        ),
        releaseVersion: json['release_version'] as String,
        patchNumber: checkedKey(json, 'patch_number') as int?,
        startedAt: maybeParseDateTime(
          checkedKey(json, 'started_at') as String?,
        ),
        rungCrossings: (json['rung_crossings'] as List)
            .map<RolloutRungCrossing>(
              (e) => RolloutRungCrossing.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        eligible: json['eligible'] as bool,
        ineligibleReason: RolloutIneligibleReason.maybeFromJson(
          json['ineligible_reason'] as String?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static RolloutSpeedSample? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return RolloutSpeedSample.fromJson(json);
  }

  /// The kind of artifact a rollout-speed sample describes.
  final RolloutArtifactType artifactType;

  /// The release this sample belongs to: the release itself for a
  /// release sample, the patch's parent release for a patch sample.
  final String releaseVersion;

  /// The patch number; null for release samples.
  final int? patchNumber;

  /// The first hour (UTC) the sample's adoption share crossed the
  /// start threshold. Null when the share never crossed it, in which
  /// case `rung_crossings` is empty.
  final DateTime? startedAt;

  /// The first crossing of each rung the sample has reached, ordered
  /// by `rung` ascending. Rungs not (yet) crossed are absent — samples
  /// are right-censored.
  final List<RolloutRungCrossing> rungCrossings;

  /// Whether the sample qualifies for aggregate statistics such as
  /// medians. Ineligible samples are still returned — flagged, never
  /// dropped — with the cause in `ineligible_reason`.
  final bool eligible;

  /// Why a rollout-speed sample does not qualify for aggregate statistics.
  /// Ineligible samples are still returned — flagged, never dropped.
  final RolloutIneligibleReason? ineligibleReason;

  /// Converts a [RolloutSpeedSample] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'artifact_type': artifactType.toJson(),
      'release_version': releaseVersion,
      'patch_number': patchNumber,
      'started_at': startedAt?.toIso8601String(),
      'rung_crossings': rungCrossings.map((e) => e.toJson()).toList(),
      'eligible': eligible,
      'ineligible_reason': ineligibleReason?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    artifactType,
    releaseVersion,
    patchNumber,
    startedAt,
    listHash(rungCrossings),
    eligible,
    ineligibleReason,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RolloutSpeedSample &&
        artifactType == other.artifactType &&
        releaseVersion == other.releaseVersion &&
        patchNumber == other.patchNumber &&
        startedAt == other.startedAt &&
        listsEqual(rungCrossings, other.rungCrossings) &&
        eligible == other.eligible &&
        ineligibleReason == other.ineligibleReason;
  }
}
