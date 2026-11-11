import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template rollback_patch_request}
/// The optional request body for POST
/// /apps/{appId}/releases/{releaseId}/patches/{patchId}/rollback.
/// {@endtemplate}
@immutable
class RollbackPatchRequest {
  /// {@macro rollback_patch_request}
  const RollbackPatchRequest({
    this.platforms,
  });

  /// Converts a `Map<String, dynamic>` to a [RollbackPatchRequest].
  factory RollbackPatchRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'RollbackPatchRequest',
      json,
      () => RollbackPatchRequest(
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static RollbackPatchRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return RollbackPatchRequest.fromJson(json);
  }

  /// The platforms whose patches under the number to roll back, at
  /// least one. Omit to roll back every platform's.
  /// Unstable: this may change shape until patch linking ships.
  final List<ReleasePlatform>? platforms;

  /// Converts a [RollbackPatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'platforms': ?platforms?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(platforms).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RollbackPatchRequest &&
        listsEqual(platforms, other.platforms);
  }
}
