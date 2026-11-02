import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_api_token.dart';

/// {@template audit_log_api}
/// OCSF `api`, the operation performed.
/// {@endtemplate}
@immutable
class AuditLogApi {
  /// {@macro audit_log_api}
  const AuditLogApi({
    required this.operation,
    this.token,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogApi].
  factory AuditLogApi.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogApi',
      json,
      () => AuditLogApi(
        operation: json['operation'] as String,
        token: AuditLogApiToken.maybeFromJson(
          json['token'] as Map<String, dynamic>?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogApi? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogApi.fromJson(json);
  }

  /// The event's name, such as `organization.rename`. The value the
  /// `operation` filter takes.
  final String operation;

  /// The API key (personal access token or service account key) the
  /// request was made with. Absent for other credentials.
  final AuditLogApiToken? token;

  /// Converts an [AuditLogApi] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'operation': operation,
      'token': ?token?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    operation,
    token,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogApi &&
        operation == other.operation &&
        token == other.token;
  }
}
