import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/organization_membership.dart';

/// {@template get_organizations_response}
/// The response body for GET /organizations.
/// {@endtemplate}
@immutable
class GetOrganizationsResponse {
  /// {@macro get_organizations_response}
  const GetOrganizationsResponse({
    required this.organizations,
    this.nextCursor,
    this.totalCount,
  });

  /// Converts a `Map<String, dynamic>` to a [GetOrganizationsResponse].
  factory GetOrganizationsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetOrganizationsResponse',
      json,
      () => GetOrganizationsResponse(
        organizations: (json['organizations'] as List)
            .map<OrganizationMembership>(
              (e) => OrganizationMembership.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
        totalCount: json['total_count'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetOrganizationsResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetOrganizationsResponse.fromJson(json);
  }

  /// Organizations that the user is a member of, as well as this user's role
  /// in each organization.
  final List<OrganizationMembership> organizations;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page`,
  /// `cursor` or `page`) and another page follows. Absent on the last
  /// page and on unpaginated responses.
  final String? nextCursor;

  /// How many items the whole list holds. Present only when the
  /// request was paginated.
  final int? totalCount;

  /// Converts a [GetOrganizationsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'organizations': organizations.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
      'total_count': ?totalCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(organizations),
    nextCursor,
    totalCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetOrganizationsResponse &&
        listsEqual(organizations, other.organizations) &&
        nextCursor == other.nextCursor &&
        totalCount == other.totalCount;
  }
}
