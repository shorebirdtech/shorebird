import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_artifact_type.dart';
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
    required this.createdAt,
    required this.rungCrossings,
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
        createdAt: DateTime.parse(json['created_at'] as String),
        rungCrossings: (json['rung_crossings'] as List)
            .map<RolloutRungCrossing>(
              (e) => RolloutRungCrossing.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
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

  /// When the artifact was created in Shorebird — the anchor every
  /// transit is measured from. For a store release this is when the
  /// release was built, so its transits include app-store review and
  /// staged-rollout time by design.
  final DateTime createdAt;

  /// The first crossing of each rung the sample has reached, ordered
  /// by `rung` ascending. Rungs not (yet) crossed are absent — samples
  /// are right-censored.
  final List<RolloutRungCrossing> rungCrossings;

  /// Converts a [RolloutSpeedSample] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'artifact_type': artifactType.toJson(),
      'release_version': releaseVersion,
      'patch_number': patchNumber,
      'created_at': createdAt.toIso8601String(),
      'rung_crossings': rungCrossings.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    artifactType,
    releaseVersion,
    patchNumber,
    createdAt,
    listHash(rungCrossings),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RolloutSpeedSample &&
        artifactType == other.artifactType &&
        releaseVersion == other.releaseVersion &&
        patchNumber == other.patchNumber &&
        createdAt == other.createdAt &&
        listsEqual(rungCrossings, other.rungCrossings);
  }
}
