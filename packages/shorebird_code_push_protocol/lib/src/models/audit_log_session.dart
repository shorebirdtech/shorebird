import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template audit_log_session}
/// The console or OAuth sign-in session the request was made under.
/// Absent for API keys.
/// {@endtemplate}
@immutable
class AuditLogSession {
  /// {@macro audit_log_session}
  const AuditLogSession({
    required this.uid,
    this.createdTime,
    this.issuer,
    this.isMfa,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogSession].
  factory AuditLogSession.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogSession',
      json,
      () => AuditLogSession(
        uid: json['uid'] as String,
        createdTime: json['created_time'] as int?,
        issuer: json['issuer'] as String?,
        isMfa: json['is_mfa'] as bool?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogSession? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogSession.fromJson(json);
  }

  /// The session's ID (never its token), as a string.
  final String uid;

  /// When the session began, in milliseconds since the Unix epoch.
  final int? createdTime;

  /// The issuer of the identity the session's holder signed in with.
  final String? issuer;

  /// Whether the sign-in used a second factor. Present only when the
  /// identity provider said; absent means unknown, not false.
  final bool? isMfa;

  /// Converts an [AuditLogSession] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'created_time': ?createdTime,
      'issuer': ?issuer,
      'is_mfa': ?isMfa,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    uid,
    createdTime,
    issuer,
    isMfa,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogSession &&
        uid == other.uid &&
        createdTime == other.createdTime &&
        issuer == other.issuer &&
        isMfa == other.isMfa;
  }
}
