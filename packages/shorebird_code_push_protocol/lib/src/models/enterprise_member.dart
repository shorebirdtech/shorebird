import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_app_grant.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_role.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_team_access.dart';
import 'package:shorebird_code_push_protocol/src/models/sign_in_method.dart';

@immutable
class EnterpriseMember {
  const EnterpriseMember({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.kind,
    required this.teams,
    required this.appGrants,
    required this.signInMethod,
    required this.signedInAt,
    required this.lastActiveAt,
    required this.role,
    required this.removedAt,
    required this.removedByEmail,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseMember].
  factory EnterpriseMember.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseMember',
      json,
      () => EnterpriseMember(
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
        role: EnterpriseRole.fromJson(json['role'] as String),
        removedAt: maybeParseDateTime(
          checkedKey(json, 'removed_at') as String?,
        ),
        removedByEmail: checkedKey(json, 'removed_by_email') as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseMember? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseMember.fromJson(json);
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

  /// A person's role in an enterprise.
  final EnterpriseRole role;

  /// When the enterprise removed them, or null.
  final DateTime? removedAt;

  /// Who removed them, or null.
  final String? removedByEmail;

  /// Converts an [EnterpriseMember] to a `Map<String, dynamic>`.
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
      'role': role.toJson(),
      'removed_at': removedAt?.toUtc().toIso8601String(),
      'removed_by_email': removedByEmail,
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
    role,
    removedAt,
    removedByEmail,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseMember &&
        userId == other.userId &&
        email == other.email &&
        displayName == other.displayName &&
        kind == other.kind &&
        listsEqual(teams, other.teams) &&
        listsEqual(appGrants, other.appGrants) &&
        signInMethod == other.signInMethod &&
        signedInAt == other.signedInAt &&
        lastActiveAt == other.lastActiveAt &&
        role == other.role &&
        removedAt == other.removedAt &&
        removedByEmail == other.removedByEmail;
  }
}
