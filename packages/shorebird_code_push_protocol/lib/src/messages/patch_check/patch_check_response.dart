// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_check_metadata.dart';

/// {@template patch_check_response}
/// The response body for POST /patches/check.
/// {@endtemplate}
@immutable
class PatchCheckResponse {
  /// {@macro patch_check_response}
  const PatchCheckResponse({
    required this.patchAvailable,
    this.patch,
    this.rolledBackPatchNumbers,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchCheckResponse].
  factory PatchCheckResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchCheckResponse',
      json,
      () => PatchCheckResponse(
        patchAvailable: json['patch_available'] as bool,
        patch: PatchCheckMetadata.maybeFromJson(
          json['patch'] as Map<String, dynamic>?,
        ),
        rolledBackPatchNumbers: (json['rolled_back_patch_numbers'] as List?)
            ?.cast<int>(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchCheckResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchCheckResponse.fromJson(json);
  }

  /// Whether a patch is available.
  final bool patchAvailable;

  /// Patch metadata representing the contents of a patch for a
  /// specific platform and architecture.
  final PatchCheckMetadata? patch;

  /// The numbers of all patches that have been rolled back for the current
  /// release.
  final List<int>? rolledBackPatchNumbers;

  /// Converts a [PatchCheckResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'patch_available': patchAvailable,
      'patch': patch?.toJson(),
      'rolled_back_patch_numbers': rolledBackPatchNumbers,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    patchAvailable,
    patch,
    listHash(rolledBackPatchNumbers),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchCheckResponse &&
        patchAvailable == other.patchAvailable &&
        patch == other.patch &&
        listsEqual(rolledBackPatchNumbers, other.rolledBackPatchNumbers);
  }
}
