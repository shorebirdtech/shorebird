import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'patch_check_response.g.dart';

/// {@template patch_check_response}
/// The response body for POST /api/v1/patches/check
/// {@endtemplate}
@JsonSerializable()
class PatchCheckResponse extends Equatable {
  /// {@macro patch_check_response}
  const PatchCheckResponse({
    required this.patchAvailable,
    this.patch,
    this.rolledBackPatchNumbers,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchCheckResponse]
  factory PatchCheckResponse.fromJson(Map<String, dynamic> json) =>
      _$PatchCheckResponseFromJson(json);

  /// Converts a [PatchCheckResponse] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$PatchCheckResponseToJson(this);

  /// Whether a patch is available.
  final bool patchAvailable;

  /// The patch metadata.
  final PatchCheckMetadata? patch;

  /// The numbers of all patches that have been rolled back for the current
  /// release.
  final List<int>? rolledBackPatchNumbers;

  @override
  List<Object?> get props => [patchAvailable, patch, rolledBackPatchNumbers];
}

/// {@template patch_check_metadata}
/// Patch metadata represents the contents of an update (patch) for a specific
/// platform and architecture.
/// {@endtemplate}
@JsonSerializable()
class PatchCheckMetadata extends Equatable {
  /// {@macro patch_check_metadata}
  const PatchCheckMetadata({
    required this.number,
    required this.downloadUrl,
    required this.hash,
    required this.hashSignature,
  });

  /// Converts a `Map<String, dynamic>` to an [PatchCheckMetadata]
  factory PatchCheckMetadata.fromJson(Map<String, dynamic> json) =>
      _$PatchCheckMetadataFromJson(json);

  /// Converts an [PatchCheckMetadata] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$PatchCheckMetadataToJson(this);

  /// The patch number associated with the artifact.
  final int number;

  /// The URL of the artifact.
  final String downloadUrl;

  /// The hash of the artifact.
  final String hash;

  /// The signature of the [hash].
  @JsonKey(includeIfNull: false)
  final String? hashSignature;

  @override
  List<Object?> get props => [number, downloadUrl, hash, hashSignature];
}
