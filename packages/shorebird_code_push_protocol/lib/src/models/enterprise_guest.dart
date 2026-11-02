import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_app_grant.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_team_access.dart';
import 'package:shorebird_code_push_protocol/src/models/sign_in_method.dart';

@immutable
class EnterpriseGuest {
  const EnterpriseGuest({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.kind,
    required this.teams,
    required this.appGrants,
    required this.signInMethod,
    required this.signedInAt,
    required this.lastActiveAt,
    required this.outsideGuestPolicy,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseGuest].
  factory EnterpriseGuest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseGuest',
      json,
      () => EnterpriseGuest(
        userId: json['user_id'] as int,
        email: checkedKey(json, 'email') as String?,
        displayName: checkedKey(json, 'display_name') as String?,
        kind: json['kind'] as String,
        teams: (json['teams'] as List)
            .map<EnterpriseTeamAccess>(
              (e) => EnterpriseTeamAccess.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        appGrants: (json['app_grants'] as List)
            .map<EnterpriseAppGrant>(
              (e) => EnterpriseAppGrant.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        signInMethod: SignInMethod.maybeFromJson(
          checkedKey(json, 'sign_in_method') as String?,
        ),
        signedInAt: maybeParseDateTime(
          checkedKey(json, 'signed_in_at') as String?,
        ),
        lastActiveAt: maybeParseDateTime(
          checkedKey(json, 'last_active_at') as String?,
        ),
        outsideGuestPolicy: json['outside_guest_policy'] as bool,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseGuest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseGuest.fromJson(json);
  }

  final int userId;
  final String? email;
  final String? displayName;

  /// What kind of account it is.
  final String kind;
  final List<EnterpriseTeamAccess> teams;
  final List<EnterpriseAppGrant> appGrants;

  /// How a person signs in, named from their identity's issuer.
  final SignInMethod? signInMethod;
  final DateTime? signedInAt;
  final DateTime? lastActiveAt;

  /// Whether the guest policy would refuse them now.
  final bool outsideGuestPolicy;

  /// Converts an [EnterpriseGuest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'email': email,
      'display_name': displayName,
      'kind': kind,
      'teams': teams.map((e) => e.toJson()).toList(),
      'app_grants': appGrants.map((e) => e.toJson()).toList(),
      'sign_in_method': signInMethod?.toJson(),
      'signed_in_at': signedInAt?.toUtc().toIso8601String(),
      'last_active_at': lastActiveAt?.toUtc().toIso8601String(),
      'outside_guest_policy': outsideGuestPolicy,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    userId,
    email,
    displayName,
    kind,
    listHash(teams),
    listHash(appGrants),
    signInMethod,
    signedInAt,
    lastActiveAt,
    outsideGuestPolicy,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseGuest &&
        userId == other.userId &&
        email == other.email &&
        displayName == other.displayName &&
        kind == other.kind &&
        listsEqual(teams, other.teams) &&
        listsEqual(appGrants, other.appGrants) &&
        signInMethod == other.signInMethod &&
        signedInAt == other.signedInAt &&
        lastActiveAt == other.lastActiveAt &&
        outsideGuestPolicy == other.outsideGuestPolicy;
  }
}
