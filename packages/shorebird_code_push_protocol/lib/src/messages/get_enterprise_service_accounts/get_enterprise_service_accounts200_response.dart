import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_app_summary.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_service_account.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_team.dart';

@immutable
class GetEnterpriseServiceAccounts200Response {
  const GetEnterpriseServiceAccounts200Response({
    required this.totalCount,
    required this.teams,
    required this.apps,
    required this.serviceAccounts,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [GetEnterpriseServiceAccounts200Response].
  factory GetEnterpriseServiceAccounts200Response.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'GetEnterpriseServiceAccounts200Response',
      json,
      () => GetEnterpriseServiceAccounts200Response(
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
        serviceAccounts: (json['service_accounts'] as List)
            .map<EnterpriseServiceAccount>(
              (e) =>
                  EnterpriseServiceAccount.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetEnterpriseServiceAccounts200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseServiceAccounts200Response.fromJson(json);
  }

  /// How many items the whole list holds.
  final int totalCount;

  /// The cursor of the next page; absent on the last page.
  final String? nextCursor;
  final List<EnterpriseTeam> teams;
  final List<EnterpriseAppSummary> apps;
  final List<EnterpriseServiceAccount> serviceAccounts;

  /// Converts a [GetEnterpriseServiceAccounts200Response]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'total_count': totalCount,
      'next_cursor': ?nextCursor,
      'teams': teams.map((e) => e.toJson()).toList(),
      'apps': apps.map((e) => e.toJson()).toList(),
      'service_accounts': serviceAccounts.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    totalCount,
    nextCursor,
    listHash(teams),
    listHash(apps),
    listHash(serviceAccounts),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetEnterpriseServiceAccounts200Response &&
        totalCount == other.totalCount &&
        nextCursor == other.nextCursor &&
        listsEqual(teams, other.teams) &&
        listsEqual(apps, other.apps) &&
        listsEqual(serviceAccounts, other.serviceAccounts);
  }
}
