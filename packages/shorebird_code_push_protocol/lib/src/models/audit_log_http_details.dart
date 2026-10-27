import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template audit_log_http_details}
/// OCSF `http_request`. Present when a user agent was recorded.
/// {@endtemplate}
@immutable
class AuditLogHttpDetails {
  /// {@macro audit_log_http_details}
  const AuditLogHttpDetails({
    required this.userAgent,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogHttpDetails].
  factory AuditLogHttpDetails.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogHttpDetails',
      json,
      () => AuditLogHttpDetails(
        userAgent: json['user_agent'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogHttpDetails? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogHttpDetails.fromJson(json);
  }

  /// The request's `User-Agent`.
  final String userAgent;

  /// Converts an [AuditLogHttpDetails] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'user_agent': userAgent,
    };
  }

  @override
  int get hashCode => userAgent.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogHttpDetails && userAgent == other.userAgent;
  }
}
