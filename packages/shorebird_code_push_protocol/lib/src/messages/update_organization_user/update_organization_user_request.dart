import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template update_organization_user_request}
/// The request body for PATCH
/// /organizations/{organizationId}/users/{userId}.
/// {@endtemplate}
@immutable
class UpdateOrganizationUserRequest {
  /// {@macro update_organization_user_request}
  const UpdateOrganizationUserRequest({
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdateOrganizationUserRequest].
  factory UpdateOrganizationUserRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UpdateOrganizationUserRequest',
      json,
      () => UpdateOrganizationUserRequest(
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdateOrganizationUserRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return UpdateOrganizationUserRequest.fromJson(json);
  }

  /// The member's new role. `owner` transfers ownership of the
  /// organization to the member.
  final Role role;

  /// Converts a [UpdateOrganizationUserRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => role.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateOrganizationUserRequest && role == other.role;
  }
}
