import 'package:json_annotation/json_annotation.dart';

part 'gcp_alert.g.dart';

/// {@template gcp_alert}
/// A GCP alert notification.
/// https://console.cloud.google.com/monitoring/alerting/notifications
///
/// For more information, see https://cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.alertPolicies.
/// For sample alerts, see https://cloud.google.com/monitoring/alerts/policies-in-json.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class GCPAlert {
  /// {@macro gcp_alert}
  const GCPAlert({this.incident});

  /// Creates a [GCPAlert] from a JSON [Map].
  factory GCPAlert.fromJson(Map<String, dynamic> json) =>
      _$GCPAlertFromJson(json);

  /// The incident associated with the alert.
  final Incident? incident;
}

/// {@template incident}
/// An incident which triggered an alert.
/// This API isn't documented and includes a lot more information
/// but we only include the properties necessary for the discord notification.
/// https://issuetracker.google.com/issues/235268835?pli=1
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class Incident {
  /// {@macro incident}
  const Incident({
    this.url,
    this.state,
    this.summary,
    this.resourceName,
    this.conditionName,
  });

  /// Creates an [Incident] from a JSON [Map].
  factory Incident.fromJson(Map<String, dynamic> json) =>
      _$IncidentFromJson(json);

  /// The URL of the incident.
  final String? url;

  /// The state of the incident.
  final String? state;

  /// A summary of the incident.
  final String? summary;

  /// The name of the resource.
  final String? resourceName;

  /// The name of the condition associated with the incident.
  final String? conditionName;
}
