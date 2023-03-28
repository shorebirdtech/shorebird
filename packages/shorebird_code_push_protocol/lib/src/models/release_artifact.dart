import 'package:json_annotation/json_annotation.dart';

part 'release_artifact.g.dart';

/// {@template release_artifact}
/// An artifact contains metadata about the contents of a specific release
/// for a specific platform and architecture.
/// {@endtemplate}
@JsonSerializable()
class ReleaseArtifact {
  /// {@macro release_artifact}
  const ReleaseArtifact({
    required this.id,
    required this.releaseId,
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    required this.url,
  });

  /// Converts a Map<String, dynamic> to a [ReleaseArtifact]
  factory ReleaseArtifact.fromJson(Map<String, dynamic> json) =>
      _$ReleaseArtifactFromJson(json);

  /// Converts a [ReleaseArtifact] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$ReleaseArtifactToJson(this);

  /// The ID of the artifact;
  final int id;

  /// The ID of the release.
  final int releaseId;

  /// The arch of the artifact.
  final String arch;

  /// The platform of the artifact.
  final String platform;

  /// The hash of the artifact.
  final String hash;

  /// The size of the artifact in bytes.
  final int size;

  /// The url of the artifact.
  final String url;
}
