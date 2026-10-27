import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_actor_user.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_session.dart';

/// {@template audit_log_actor}
/// OCSF `actor`, who caused the entry.
/// {@endtemplate}
@immutable
class AuditLogActor {
  /// {@macro audit_log_actor}
  const AuditLogActor({
    required this.user,
    this.session,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogActor].
  factory AuditLogActor.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogActor',
      json,
      () => AuditLogActor(
        user: AuditLogActorUser.fromJson(json['user'] as Map<String, dynamic>),
        session: AuditLogSession.maybeFromJson(
          json['session'] as Map<String, dynamic>?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogActor? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogActor.fromJson(json);
  }

  /// OCSF `actor.user`. A person is type 1 (`User`), a service account or
  /// a CI job acting as one is type 4 (`Service`), and Shorebird staff
  /// are type 99 (`shorebird_staff`) with no identity beyond that name.
  final AuditLogActorUser user;

  /// The console or OAuth sign-in session the request was made under.
  /// Absent for API keys.
  final AuditLogSession? session;

  /// Converts an [AuditLogActor] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'session': ?session?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    user,
    session,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogActor &&
        user == other.user &&
        session == other.session;
  }
}
