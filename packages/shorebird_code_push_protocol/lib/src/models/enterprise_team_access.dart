import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

@immutable
class EnterpriseTeamAccess {
  const EnterpriseTeamAccess({
    required this.teamId,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseTeamAccess].
  factory EnterpriseTeamAccess.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseTeamAccess',
      json,
      () => EnterpriseTeamAccess(
        teamId: json['team_id'] as int,
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseTeamAccess? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseTeamAccess.fromJson(json);
  }

  final int teamId;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [EnterpriseTeamAccess] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'team_id': teamId,
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    teamId,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseTeamAccess &&
        teamId == other.teamId &&
        role == other.role;
  }
}
