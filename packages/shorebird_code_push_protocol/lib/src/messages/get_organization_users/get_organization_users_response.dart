// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/organization_user.dart';

/// {@template get_organization_users_response}
/// The response body for GET /organizations/{organizationId}/users.
/// {@endtemplate}
@immutable
class GetOrganizationUsersResponse {
  /// {@macro get_organization_users_response}
  const GetOrganizationUsersResponse({
    required this.users,
  });

  /// Converts a `Map<String, dynamic>` to a [GetOrganizationUsersResponse].
  factory GetOrganizationUsersResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetOrganizationUsersResponse',
      json,
      () => GetOrganizationUsersResponse(
        users: (json['users'] as List)
            .map<OrganizationUser>(
              (e) => OrganizationUser.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetOrganizationUsersResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetOrganizationUsersResponse.fromJson(json);
  }

  /// The list of users that belong to the organization, as well as their
  /// roles in the organization.
  final List<OrganizationUser> users;

  /// Converts a [GetOrganizationUsersResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'users': users.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(users).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetOrganizationUsersResponse &&
        listsEqual(users, other.users);
  }
}
