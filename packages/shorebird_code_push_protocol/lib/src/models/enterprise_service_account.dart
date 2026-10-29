import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template enterprise_service_account}
/// A service account one of an enterprise's organizations owns.
/// {@endtemplate}
@immutable
class EnterpriseServiceAccount {
  /// {@macro enterprise_service_account}
  const EnterpriseServiceAccount({
    required this.userId,
    required this.name,
    required this.teamId,
    required this.role,
    required this.createdAt,
    required this.lastAuthAt,
    required this.createdByEmail,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseServiceAccount].
  factory EnterpriseServiceAccount.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseServiceAccount',
      json,
      () => EnterpriseServiceAccount(
        userId: json['user_id'] as int,
        name: json['name'] as String,
        teamId: json['team_id'] as int,
        role: Role.fromJson(json['role'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        lastAuthAt: maybeParseDateTime(
          checkedKey(json, 'last_auth_at') as String?,
        ),
        createdByEmail: checkedKey(json, 'created_by_email') as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseServiceAccount? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseServiceAccount.fromJson(json);
  }

  final int userId;
  final String name;
  final int teamId;

  /// A role that a user can have relative to an Organization or App.
  final Role role;
  final DateTime createdAt;
  final DateTime? lastAuthAt;
  final String? createdByEmail;

  /// Converts an [EnterpriseServiceAccount] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'team_id': teamId,
      'role': role.toJson(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'last_auth_at': lastAuthAt?.toUtc().toIso8601String(),
      'created_by_email': createdByEmail,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    userId,
    name,
    teamId,
    role,
    createdAt,
    lastAuthAt,
    createdByEmail,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseServiceAccount &&
        userId == other.userId &&
        name == other.name &&
        teamId == other.teamId &&
        role == other.role &&
        createdAt == other.createdAt &&
        lastAuthAt == other.lastAuthAt &&
        createdByEmail == other.createdByEmail;
  }
}
