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
    this.nextCursor,
    this.totalCount,
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
        nextCursor: json['next_cursor'] as String?,
        totalCount: json['total_count'] as int?,
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

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page`,
  /// `cursor` or `page`) and another page follows. Absent on the last
  /// page and on unpaginated responses.
  final String? nextCursor;

  /// How many items the whole list holds. Present only when the
  /// request was paginated.
  final int? totalCount;

  /// Converts a [GetOrganizationUsersResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'users': users.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
      'total_count': ?totalCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(users),
    nextCursor,
    totalCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetOrganizationUsersResponse &&
        listsEqual(users, other.users) &&
        nextCursor == other.nextCursor &&
        totalCount == other.totalCount;
  }
}
