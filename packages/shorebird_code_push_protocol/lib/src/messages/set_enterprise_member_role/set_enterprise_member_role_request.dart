import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_role.dart';

@immutable
class SetEnterpriseMemberRoleRequest {
  const SetEnterpriseMemberRoleRequest({
    this.role,
  });

  /// Converts a `Map<String, dynamic>` to a [SetEnterpriseMemberRoleRequest].
  factory SetEnterpriseMemberRoleRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'SetEnterpriseMemberRoleRequest',
      json,
      () => SetEnterpriseMemberRoleRequest(
        role: EnterpriseRole.maybeFromJson(json['role'] as String?),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static SetEnterpriseMemberRoleRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return SetEnterpriseMemberRoleRequest.fromJson(json);
  }

  /// A person's role in an enterprise.
  final EnterpriseRole? role;

  /// Converts a [SetEnterpriseMemberRoleRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'role': ?role?.toJson(),
    };
  }

  @override
  int get hashCode => role.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SetEnterpriseMemberRoleRequest && role == other.role;
  }
}
