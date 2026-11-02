import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/organization_user.dart';

@immutable
class GetEnterpriseOrganizationMembers200Response {
  const GetEnterpriseOrganizationMembers200Response({
    required this.totalCount,
    required this.users,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [GetEnterpriseOrganizationMembers200Response].
  factory GetEnterpriseOrganizationMembers200Response.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'GetEnterpriseOrganizationMembers200Response',
      json,
      () => GetEnterpriseOrganizationMembers200Response(
        totalCount: json['total_count'] as int,
        nextCursor: json['next_cursor'] as String?,
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
  static GetEnterpriseOrganizationMembers200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseOrganizationMembers200Response.fromJson(json);
  }

  /// How many items the whole list holds.
  final int totalCount;

  /// The cursor of the next page; absent on the last page.
  final String? nextCursor;
  final List<OrganizationUser> users;

  /// Converts a [GetEnterpriseOrganizationMembers200Response]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'total_count': totalCount,
      'next_cursor': ?nextCursor,
      'users': users.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    totalCount,
    nextCursor,
    listHash(users),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetEnterpriseOrganizationMembers200Response &&
        totalCount == other.totalCount &&
        nextCursor == other.nextCursor &&
        listsEqual(users, other.users);
  }
}
