import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_event.dart';

/// {@template get_organization_audit_logs_response}
/// The response body for GET /organizations/{organizationId}/audit-logs.
/// {@endtemplate}
@immutable
class GetOrganizationAuditLogsResponse {
  /// {@macro get_organization_audit_logs_response}
  const GetOrganizationAuditLogsResponse({
    required this.data,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetOrganizationAuditLogsResponse].
  factory GetOrganizationAuditLogsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetOrganizationAuditLogsResponse',
      json,
      () => GetOrganizationAuditLogsResponse(
        data: (json['data'] as List)
            .map<AuditLogEvent>(
              (e) => AuditLogEvent.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetOrganizationAuditLogsResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetOrganizationAuditLogsResponse.fromJson(json);
  }

  /// The entries on this page, in the requested order.
  final List<AuditLogEvent> data;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page. Newest first, absent on the last page. Oldest
  /// first, always present: the last entry's position, or the cursor
  /// that was sent when the page is empty.
  final String? nextCursor;

  /// Converts a [GetOrganizationAuditLogsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'data': data.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(data),
    nextCursor,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetOrganizationAuditLogsResponse &&
        listsEqual(data, other.data) &&
        nextCursor == other.nextCursor;
  }
}
