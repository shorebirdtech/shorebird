import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_actor_user_type.dart';

/// {@template audit_log_actor_user}
/// OCSF `actor.user`. A person is type 1 (`User`), a service account or
/// a CI job acting as one is type 4 (`Service`), and Shorebird staff
/// are type 99 (`shorebird_staff`) with no identity beyond that name.
/// {@endtemplate}
@immutable
class AuditLogActorUser {
  /// {@macro audit_log_actor_user}
  const AuditLogActorUser({
    required this.typeId,
    required this.type,
    this.uid,
    this.name,
    this.emailAddr,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogActorUser].
  factory AuditLogActorUser.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogActorUser',
      json,
      () => AuditLogActorUser(
        uid: json['uid'] as String?,
        name: json['name'] as String?,
        emailAddr: json['email_addr'] as String?,
        typeId: json['type_id'] as int,
        type: AuditLogActorUserType.fromJson(json['type'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogActorUser? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogActorUser.fromJson(json);
  }

  /// The user's or service account's ID, as a string, when known.
  final String? uid;

  /// The actor's name, when known.
  final String? name;

  /// The actor's email, when known.
  final String? emailAddr;

  /// 1 for a person, 4 for a service account, 99 for Shorebird staff.
  final int typeId;

  /// The name of `type_id`.
  final AuditLogActorUserType type;

  /// Converts an [AuditLogActorUser] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'uid': ?uid,
      'name': ?name,
      'email_addr': ?emailAddr,
      'type_id': typeId,
      'type': type.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    uid,
    name,
    emailAddr,
    typeId,
    type,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogActorUser &&
        uid == other.uid &&
        name == other.name &&
        emailAddr == other.emailAddr &&
        typeId == other.typeId &&
        type == other.type;
  }
}
