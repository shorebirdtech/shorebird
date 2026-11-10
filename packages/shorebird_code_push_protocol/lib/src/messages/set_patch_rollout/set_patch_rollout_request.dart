import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template set_patch_rollout_request}
/// The request body for PUT
/// /apps/{appId}/releases/{releaseId}/patches/{patchId}/rollout.
/// {@endtemplate}
@immutable
class SetPatchRolloutRequest {
  /// {@macro set_patch_rollout_request}
  const SetPatchRolloutRequest({
    required this.rolloutPercentage,
  });

  /// Converts a `Map<String, dynamic>` to a [SetPatchRolloutRequest].
  factory SetPatchRolloutRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'SetPatchRolloutRequest',
      json,
      () => SetPatchRolloutRequest(
        rolloutPercentage: (json['rollout_percentage'] as num).toDouble(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static SetPatchRolloutRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return SetPatchRolloutRequest.fromJson(json);
  }

  /// The percentage of the channel's devices to offer the patch to, a
  /// multiple of 0.01 from 0.01 to 100, no lower than the patch's
  /// current one.
  final double rolloutPercentage;

  /// Converts a [SetPatchRolloutRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'rollout_percentage': rolloutPercentage,
    };
  }

  @override
  int get hashCode => rolloutPercentage.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SetPatchRolloutRequest &&
        rolloutPercentage == other.rolloutPercentage;
  }
}
