import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template update_user_request}
/// The request body for PATCH /users/me. A field left out is left
/// unchanged.
/// {@endtemplate}
@immutable
class UpdateUserRequest {
  /// {@macro update_user_request}
  const UpdateUserRequest({
    this.displayName,
    this.patchOverageLimit,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdateUserRequest].
  factory UpdateUserRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UpdateUserRequest',
      json,
      () => UpdateUserRequest(
        displayName: json['display_name'] as String?,
        patchOverageLimit: json['patch_overage_limit'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdateUserRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UpdateUserRequest.fromJson(json);
  }

  /// The user's new display name. At most 256 characters.
  final String? displayName;

  /// The most patch installs past the plan's allotment the user
  /// agrees to pay for each overage period. `0` turns overage off;
  /// `null` removes the limit. Must not be negative.
  final int? patchOverageLimit;

  /// Converts a [UpdateUserRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'display_name': ?displayName,
      'patch_overage_limit': patchOverageLimit,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    displayName,
    patchOverageLimit,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateUserRequest &&
        displayName == other.displayName &&
        patchOverageLimit == other.patchOverageLimit;
  }
}
