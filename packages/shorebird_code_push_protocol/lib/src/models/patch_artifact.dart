import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'patch_artifact.g.dart';

/// {@template patch_artifact}
/// An artifact contains metadata about the contents of a specific patch
/// for a specific platform and architecture.
/// {@endtemplate}
@JsonSerializable()
class PatchArtifact {
  /// {@macro patch_artifact}
  const PatchArtifact({
    required this.id,
    required this.patchId,
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    required this.url,
  });

  /// Converts a Map<String, dynamic> to a [PatchArtifact]
  factory PatchArtifact.fromJson(Map<String, dynamic> json) =>
      _$PatchArtifactFromJson(json);

  /// Converts a [PatchArtifact] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$PatchArtifactToJson(this);

  /// The ID of the artifact;
  final int id;

  /// The ID of the patch.
  final int patchId;

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
}
