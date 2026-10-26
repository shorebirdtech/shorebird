import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template get_patch_limit_exceeded_response}
/// The response body for GET /usage/patch_limit_exceeded.
/// {@endtemplate}
@immutable
class GetPatchLimitExceededResponse {
  /// {@macro get_patch_limit_exceeded_response}
  const GetPatchLimitExceededResponse({
    required this.patchLimitExceeded,
  });

  /// Converts a `Map<String, dynamic>` to a [GetPatchLimitExceededResponse].
  factory GetPatchLimitExceededResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetPatchLimitExceededResponse',
      json,
      () => GetPatchLimitExceededResponse(
        patchLimitExceeded: json['patch_limit_exceeded'] as bool,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetPatchLimitExceededResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetPatchLimitExceededResponse.fromJson(json);
  }

  /// Whether the account has reached the install count at which
  /// patches stop being served. `false` when it cannot be
  /// determined.
  final bool patchLimitExceeded;

  /// Converts a [GetPatchLimitExceededResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'patch_limit_exceeded': patchLimitExceeded,
    };
  }

  @override
  int get hashCode => patchLimitExceeded.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetPatchLimitExceededResponse &&
        patchLimitExceeded == other.patchLimitExceeded;
  }
}
