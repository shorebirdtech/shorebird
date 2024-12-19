import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

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
    required this.podfileLockHash,
    required this.canSideload,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleaseArtifact]
  factory ReleaseArtifact.fromJson(Map<String, dynamic> json) =>
      _$ReleaseArtifactFromJson(json);

  /// Converts a [ReleaseArtifact] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$ReleaseArtifactToJson(this);

  /// The ID of the artifact;
  final int id;

  /// The ID of the release.
  final int releaseId;

  /// The arch of the artifact.
  final String arch;

  /// The platform of the artifact.
  final ReleasePlatform platform;

  /// The hash of the artifact.
  final String hash;

  /// The size of the artifact in bytes.
  final int size;

  /// The url of the artifact.
  final String url;

  /// The hash of the Podfile.lock file used to create the artifact (iOS only).
  final String? podfileLockHash;

  /// Whether the artifact can be sideloaded onto a device or not
  /// (e.g. non signed iOS artifacts cannot be sideloaded).
  final bool canSideload;

  @override
  String toString() => toJson().toString();
}
