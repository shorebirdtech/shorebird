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

  /// Patch numbers for a given release mapped to their artifacts.
  final Map<int, List<PatchArtifact>> patches;
}
