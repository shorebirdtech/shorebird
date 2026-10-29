import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_team.dart';

@immutable
class GetEnterpriseOrganizations200Response {
  const GetEnterpriseOrganizations200Response({
    required this.totalCount,
    required this.organizations,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [GetEnterpriseOrganizations200Response].
  factory GetEnterpriseOrganizations200Response.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'GetEnterpriseOrganizations200Response',
      json,
      () => GetEnterpriseOrganizations200Response(
        totalCount: json['total_count'] as int,
        nextCursor: json['next_cursor'] as String?,
        organizations: (json['organizations'] as List)
            .map<EnterpriseTeam>(
              (e) => EnterpriseTeam.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetEnterpriseOrganizations200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseOrganizations200Response.fromJson(json);
  }

  /// How many items the whole list holds.
  final int totalCount;

  /// The cursor of the next page; absent on the last page.
  final String? nextCursor;
  final List<EnterpriseTeam> organizations;

  /// Converts a [GetEnterpriseOrganizations200Response]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'total_count': totalCount,
      'next_cursor': ?nextCursor,
      'organizations': organizations.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    totalCount,
    nextCursor,
    listHash(organizations),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetEnterpriseOrganizations200Response &&
        totalCount == other.totalCount &&
        nextCursor == other.nextCursor &&
        listsEqual(organizations, other.organizations);
  }
}
