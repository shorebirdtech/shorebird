import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_artifact.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

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
    this.notes,
    this.platform,
    this.linkKey,
    this.gitSha,
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
        notes: json['notes'] as String?,
        platform: ReleasePlatform.maybeFromJson(json['platform'] as String?),
        linkKey: json['link_key'] as String?,
        gitSha: json['git_sha'] as String?,
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

  /// Freeform notes associated with the patch, if any.
  final String? notes;

  /// The platform the patch was built for. Absent on patches created
  /// before the server recorded it; read those from `artifacts`.
  /// Unstable: this may change shape until patch linking ships.
  final ReleasePlatform? platform;

  /// The key the patch was created with, which patches for other
  /// platforms under the same number share. Absent when it was
  /// created without one.
  /// Unstable: this may change shape until patch linking ships.
  final String? linkKey;

  /// The commit the patch was built from, when it was built in a git
  /// checkout. Unstable: this may change shape until patch linking ships.
  final String? gitSha;

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
      'notes': ?notes,
      'platform': ?platform?.toJson(),
      'link_key': ?linkKey,
      'git_sha': ?gitSha,
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
    notes,
    platform,
    linkKey,
    gitSha,
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
        notes == other.notes &&
        platform == other.platform &&
        linkKey == other.linkKey &&
        gitSha == other.gitSha;
  }
}
