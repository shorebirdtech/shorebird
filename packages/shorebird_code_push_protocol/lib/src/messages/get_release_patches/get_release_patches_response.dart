// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_patch.dart';

/// {@template get_release_patches_response}
/// The response to GET /apps/{appId}/releases/{releaseId}/patches.
/// {@endtemplate}
@immutable
class GetReleasePatchesResponse {
  /// {@macro get_release_patches_response}
  const GetReleasePatchesResponse({
    required this.patches,
  });

  /// Converts a `Map<String, dynamic>` to a [GetReleasePatchesResponse].
  factory GetReleasePatchesResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetReleasePatchesResponse',
      json,
      () => GetReleasePatchesResponse(
        patches: (json['patches'] as List)
            .map<ReleasePatch>(
              (e) => ReleasePatch.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetReleasePatchesResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetReleasePatchesResponse.fromJson(json);
  }

  /// List of patches.
  final List<ReleasePatch> patches;

  /// Converts a [GetReleasePatchesResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'patches': patches.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(patches).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetReleasePatchesResponse &&
        listsEqual(patches, other.patches);
  }
}
