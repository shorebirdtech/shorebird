import 'package:json_annotation/json_annotation.dart';

part 'patch_artifact.g.dart';

/// {@template patch_artifact}
/// A patch artifact represents the contents of an update (patch) for a specific
/// platform and architecture.
/// {@endtemplate}
@JsonSerializable()
class PatchArtifact {
  /// {@macro patch_PatchArtifact}
  const PatchArtifact({
    required this.patchNumber,
    required this.downloadUrl,
    required this.hash,
  });

  /// Converts a Map<String, dynamic> to an [PatchArtifact]
  factory PatchArtifact.fromJson(Map<String, dynamic> json) =>
      _$PatchArtifactFromJson(json);

  /// Converts an [PatchArtifact] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$PatchArtifactToJson(this);

  /// The patch number associated with the artifact.
  final int patchNumber;

  /// The URL of the artifact.
  final String downloadUrl;

  /// The hash of the artifact.
  final String hash;
}
