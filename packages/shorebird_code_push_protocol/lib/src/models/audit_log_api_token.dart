import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template audit_log_api_token}
/// The API key (personal access token or service account key) the
/// request was made with. Absent for other credentials.
/// {@endtemplate}
@immutable
class AuditLogApiToken {
  /// {@macro audit_log_api_token}
  const AuditLogApiToken({
    required this.uid,
    this.name,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogApiToken].
  factory AuditLogApiToken.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogApiToken',
      json,
      () => AuditLogApiToken(
        uid: json['uid'] as String,
        name: json['name'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogApiToken? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogApiToken.fromJson(json);
  }

  /// The key's ID, which revoking it takes.
  final String uid;

  /// The key's name when the entry was recorded.
  final String? name;

  /// Always 7, OCSF's API Token.
  int get typeId => 7;

  /// Always `API Token`.
  String get type => 'API Token';

  /// Converts an [AuditLogApiToken] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': ?name,
      'type_id': typeId,
      'type': type,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    uid,
    name,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogApiToken && uid == other.uid && name == other.name;
  }
}
