import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_release_patches_response.g.dart';

/// {@template get_release_patches_response}
/// The response to /api/v1/apps/$appId/releases/$releaseId/patches
/// {@endtemplate}
@JsonSerializable()
class GetReleasePatchesResponse {
  /// {@macro get_release_patches_response}
  const GetReleasePatchesResponse({required this.patches});

  /// Converts a Map<String, dynamic> to a [GetReleasePatchesResponse]
  factory GetReleasePatchesResponse.fromJson(Map<String, dynamic> json) =>
      _$GetReleasePatchesResponseFromJson(json);

  /// Converts a [GetReleasePatchesResponse] to a Map<String, dynamic>
  Json toJson() => _$GetReleasePatchesResponseToJson(this);

  /// List of patches.
  final List<ReleasePatch> patches;
}

/// {@template release_patch}
/// A patch for a given release.
/// {@endtemplate}
@JsonSerializable()
class ReleasePatch {
  /// {@macro release_patch}
  const ReleasePatch({
    required this.id,
    required this.number,
    required this.channel,
    required this.artifacts,
  });

  /// Converts a Map<String, dynamic> to a [ReleasePatch]
  factory ReleasePatch.fromJson(Map<String, dynamic> json) =>
      _$ReleasePatchFromJson(json);

  /// Converts a [ReleasePatch] to a Map<String, dynamic>
  Json toJson() => _$ReleasePatchToJson(this);

  /// The patch id.
  final int id;

  /// The patch number.
  final int number;

  /// The channel associated with the patch.
  final String? channel;

  /// The associated patch artifacts.
  final List<PatchArtifact> artifacts;
}
