import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_app_summary.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_member.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_team.dart';

@immutable
class GetEnterpriseMembers200Response {
  const GetEnterpriseMembers200Response({
    required this.totalCount,
    required this.teams,
    required this.apps,
    required this.members,
    required this.memberCount,
    required this.removedCount,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetEnterpriseMembers200Response].
  factory GetEnterpriseMembers200Response.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetEnterpriseMembers200Response',
      json,
      () => GetEnterpriseMembers200Response(
        totalCount: json['total_count'] as int,
        nextCursor: json['next_cursor'] as String?,
        teams: (json['teams'] as List)
            .map<EnterpriseTeam>(
              (e) => EnterpriseTeam.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        apps: (json['apps'] as List)
            .map<EnterpriseAppSummary>(
              (e) => EnterpriseAppSummary.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        members: (json['members'] as List)
            .map<EnterpriseMember>(
              (e) => EnterpriseMember.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        memberCount: json['member_count'] as int,
        removedCount: json['removed_count'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetEnterpriseMembers200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseMembers200Response.fromJson(json);
  }

  /// How many items the whole list holds.
  final int totalCount;

  /// The cursor of the next page; absent on the last page.
  final String? nextCursor;
  final List<EnterpriseTeam> teams;
  final List<EnterpriseAppSummary> apps;
  final List<EnterpriseMember> members;

  /// How many members it has not removed.
  final int memberCount;

  /// How many members it has removed.
  final int removedCount;

  /// Converts a [GetEnterpriseMembers200Response] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'total_count': totalCount,
      'next_cursor': ?nextCursor,
      'teams': teams.map((e) => e.toJson()).toList(),
      'apps': apps.map((e) => e.toJson()).toList(),
      'members': members.map((e) => e.toJson()).toList(),
      'member_count': memberCount,
      'removed_count': removedCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    totalCount,
    nextCursor,
    listHash(teams),
    listHash(apps),
    listHash(members),
    memberCount,
    removedCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetEnterpriseMembers200Response &&
        totalCount == other.totalCount &&
        nextCursor == other.nextCursor &&
        listsEqual(teams, other.teams) &&
        listsEqual(apps, other.apps) &&
        listsEqual(members, other.members) &&
        memberCount == other.memberCount &&
        removedCount == other.removedCount;
  }
}
