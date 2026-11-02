import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_app_summary.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_guest.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_team.dart';

@immutable
class GetEnterpriseGuests200Response {
  const GetEnterpriseGuests200Response({
    required this.totalCount,
    required this.teams,
    required this.apps,
    required this.guests,
    required this.outsideGuestPolicyCount,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetEnterpriseGuests200Response].
  factory GetEnterpriseGuests200Response.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetEnterpriseGuests200Response',
      json,
      () => GetEnterpriseGuests200Response(
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
        guests: (json['guests'] as List)
            .map<EnterpriseGuest>(
              (e) => EnterpriseGuest.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        outsideGuestPolicyCount: json['outside_guest_policy_count'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetEnterpriseGuests200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetEnterpriseGuests200Response.fromJson(json);
  }

  /// How many items the whole list holds.
  final int totalCount;

  /// The cursor of the next page; absent on the last page.
  final String? nextCursor;
  final List<EnterpriseTeam> teams;
  final List<EnterpriseAppSummary> apps;
  final List<EnterpriseGuest> guests;

  /// How many guests the policy would refuse now.
  final int outsideGuestPolicyCount;

  /// Converts a [GetEnterpriseGuests200Response] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'total_count': totalCount,
      'next_cursor': ?nextCursor,
      'teams': teams.map((e) => e.toJson()).toList(),
      'apps': apps.map((e) => e.toJson()).toList(),
      'guests': guests.map((e) => e.toJson()).toList(),
      'outside_guest_policy_count': outsideGuestPolicyCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    totalCount,
    nextCursor,
    listHash(teams),
    listHash(apps),
    listHash(guests),
    outsideGuestPolicyCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetEnterpriseGuests200Response &&
        totalCount == other.totalCount &&
        nextCursor == other.nextCursor &&
        listsEqual(teams, other.teams) &&
        listsEqual(apps, other.apps) &&
        listsEqual(guests, other.guests) &&
        outsideGuestPolicyCount == other.outsideGuestPolicyCount;
  }
}
