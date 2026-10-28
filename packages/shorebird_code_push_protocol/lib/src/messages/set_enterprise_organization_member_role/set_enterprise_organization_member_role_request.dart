import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

@immutable
class SetEnterpriseOrganizationMemberRoleRequest {
  const SetEnterpriseOrganizationMemberRoleRequest({
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [SetEnterpriseOrganizationMemberRoleRequest].
  factory SetEnterpriseOrganizationMemberRoleRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'SetEnterpriseOrganizationMemberRoleRequest',
      json,
      () => SetEnterpriseOrganizationMemberRoleRequest(
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static SetEnterpriseOrganizationMemberRoleRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return SetEnterpriseOrganizationMemberRoleRequest.fromJson(json);
  }

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts a [SetEnterpriseOrganizationMemberRoleRequest]
  /// to a `Map<String, dynamic>`.
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
    return other is SetEnterpriseOrganizationMemberRoleRequest &&
        role == other.role;
  }
}
