import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_actor.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_api.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_event_metadata.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_http_details.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_resource.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_source_endpoint.dart';

/// {@template audit_log_event}
/// One audit log entry, as an OCSF 1.9.0 API Activity event
/// (https://schema.ocsf.io/1.9.0/classes/api_activity). Fields OCSF has
/// no place for are in `unmapped`.
///
/// An entry Shorebird staff caused names its actor only as
/// `Shorebird staff`, and carries no key, session, IP address or user
/// agent.
/// {@endtemplate}
@immutable
class AuditLogEvent {
  /// {@macro audit_log_event}
  const AuditLogEvent({
    required this.activityId,
    required this.typeUid,
    required this.time,
    required this.metadata,
    required this.api,
    required this.actor,
    required this.srcEndpoint,
    required this.resources,
    required this.unmapped,
    this.httpRequest,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogEvent].
  factory AuditLogEvent.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogEvent',
      json,
      () => AuditLogEvent(
        activityId: json['activity_id'] as int,
        typeUid: json['type_uid'] as int,
        time: json['time'] as int,
        metadata: AuditLogEventMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>,
        ),
        api: AuditLogApi.fromJson(json['api'] as Map<String, dynamic>),
        actor: AuditLogActor.fromJson(json['actor'] as Map<String, dynamic>),
        srcEndpoint: AuditLogSourceEndpoint.fromJson(
          json['src_endpoint'] as Map<String, dynamic>,
        ),
        httpRequest: AuditLogHttpDetails.maybeFromJson(
          json['http_request'] as Map<String, dynamic>?,
        ),
        resources: (json['resources'] as List)
            .map<AuditLogResource>(
              (e) => AuditLogResource.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        unmapped: json['unmapped'] as Map<String, dynamic>,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogEvent? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogEvent.fromJson(json);
  }

  /// The OCSF class, always API Activity (6003).
  int get classUid => 6003;

  /// The OCSF category, always Application Activity (6).
  int get categoryUid => 6;

  /// What kind of operation this was: 1 create, 2 read, 3 update,
  /// 4 delete (or revoke), 99 other (such as a refused request).
  final int activityId;

  /// `class_uid * 100 + activity_id`, as OCSF defines it.
  final int typeUid;

  /// When the entry was recorded, in milliseconds since the Unix epoch.
  final int time;

  /// Always 1 (Informational).
  int get severityId => 1;

  /// Always 1 (Success).
  int get statusId => 1;

  /// OCSF `metadata` for an audit log entry.
  final AuditLogEventMetadata metadata;

  /// OCSF `api`, the operation performed.
  final AuditLogApi api;

  /// OCSF `actor`, who caused the entry.
  final AuditLogActor actor;

  /// OCSF `src_endpoint`, where the request came from: `ip` when it was
  /// recorded, otherwise `name` set to `unknown`.
  final AuditLogSourceEndpoint srcEndpoint;

  /// OCSF `http_request`. Present when a user agent was recorded.
  final AuditLogHttpDetails? httpRequest;

  /// What the operation acted on. Always exactly one entry.
  final List<AuditLogResource> resources;

  /// Fields OCSF has no place for, keyed in snake_case: the event's
  /// own metadata (which varies by event, nested keys included),
  /// `app_id` when the entry is about an app, and `actor_source`, the
  /// kind of credential that acted (for example `session`, `api_key`,
  /// `service_account`, `federated` or `admin_api`), when known.
  final Map<String, dynamic> unmapped;

  /// Converts an [AuditLogEvent] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'class_uid': classUid,
      'category_uid': categoryUid,
      'activity_id': activityId,
      'type_uid': typeUid,
      'time': time,
      'severity_id': severityId,
      'status_id': statusId,
      'metadata': metadata.toJson(),
      'api': api.toJson(),
      'actor': actor.toJson(),
      'src_endpoint': srcEndpoint.toJson(),
      'http_request': ?httpRequest?.toJson(),
      'resources': resources.map((e) => e.toJson()).toList(),
      'unmapped': unmapped,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    activityId,
    typeUid,
    time,
    metadata,
    api,
    actor,
    srcEndpoint,
    httpRequest,
    listHash(resources),
    mapHash(unmapped),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogEvent &&
        activityId == other.activityId &&
        typeUid == other.typeUid &&
        time == other.time &&
        metadata == other.metadata &&
        api == other.api &&
        actor == other.actor &&
        srcEndpoint == other.srcEndpoint &&
        httpRequest == other.httpRequest &&
        listsEqual(resources, other.resources) &&
        mapsEqual(unmapped, other.unmapped);
  }
}
