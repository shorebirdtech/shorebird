import 'package:json_annotation/json_annotation.dart';

part 'check_for_patches_response.g.dart';

/// {@template check_for_patches_response}
/// The response body for POST /api/v1/patches/check
/// {@endtemplate}
@JsonSerializable(createFactory: false)
class CheckForPatchesResponse {
  /// {@macro check_for_patches_response}
  const CheckForPatchesResponse({required this.patchAvailable, this.patch});

  /// Converts a [CheckForPatchesResponse] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CheckForPatchesResponseToJson(this);

  /// Whether a patch is available.
  final bool patchAvailable;

  /// The patch metadata.
  final PatchMetadata? patch;
}

/// {@template patch_metadata}
/// Patch metadata represents the contents of an update (patch) for a specific
/// platform and architecture.
/// {@endtemplate}
@JsonSerializable(createFactory: false)
class PatchMetadata {
  /// {@macro patch_metadata}
  const PatchMetadata({
    required this.number,
    required this.downloadUrl,
    required this.hash,
  });

  /// Converts an [PatchMetadata] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$PatchMetadataToJson(this);

  /// The patch number associated with the artifact.
  final int number;

  /// The URL of the artifact.
  final String downloadUrl;

  /// The hash of the artifact.
  final String hash;
}
