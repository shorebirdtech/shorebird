import 'package:json_annotation/json_annotation.dart';

part 'gcp_alert.g.dart';

/// {@template gcp_alert}
/// A GCP alert notification.
/// https://console.cloud.google.com/monitoring/alerting/notifications
///
/// For sample alerts, see https://cloud.google.com/monitoring/alerts/policies-in-json.
/// {@endtemplate}
@JsonSerializable()
class GCPAlert {
  /// {@macro gcp_alert}
  const GCPAlert({this.version, this.incident});

  /// Creates a [GCPAlert] from a JSON [Map].
  factory GCPAlert.fromJson(Map<String, dynamic> json) =>
      _$GCPAlertFromJson(json);

  /// Converts a [GCPAlert] to the JSON representation.
  Map<String, dynamic> toJson() => _$GCPAlertToJson(this);

  /// The version of the alert.
  final String? version;

  /// The incident associated with the alert.
  final Incident? incident;
}

/// {@template incident}
/// An incident which triggered an alert.
/// {@endtemplate}
@JsonSerializable()
class Incident {
  /// {@macro incident}
  const Incident({
    this.incidentId,
    this.scopingProjectId,
    this.scopingProjectNumber,
    this.url,
    this.startedAt,
    this.endedAt,
    this.state,
    this.summary,
    this.observedValue,
    this.resource,
    this.resourceTypeDisplayName,
    this.resourceId,
    this.resourceDisplayName,
    this.resourceName,
    this.metric,
    this.policyName,
    this.documentation,
    this.condition,
    this.conditionName,
    this.thresholdValue,
  });

  /// Creates an [Incident] from a JSON [Map].
  factory Incident.fromJson(Map<String, dynamic> json) =>
      _$IncidentFromJson(json);

  /// Converts an [Incident] to the JSON representation.
  Map<String, dynamic> toJson() => _$IncidentToJson(this);

  /// The unique identifier of the incident.
  final String? incidentId;

  /// The project ID of the scoping project.
  final String? scopingProjectId;

  /// The project number of the scoping project.
  final int? scopingProjectNumber;

  /// The URL of the incident.
  final String? url;

  /// The time the incident started.
  final int? startedAt;

  /// The time the incident ended.
  final int? endedAt;

  /// The state of the incident.
  final String? state;

  /// A summary of the incident.
  final String? summary;

  /// The observed value of the incident.
  final String? observedValue;

  /// The resource associated with the incident.
  final Resource? resource;

  /// The display name of the resource type.
  final String? resourceTypeDisplayName;

  /// The unique identifier of the resource.
  final String? resourceId;

  /// The display name of the resource.
  final String? resourceDisplayName;

  /// The name of the resource.
  final String? resourceName;

  /// The metric associated with the incident.
  final Metric? metric;

  /// The name of the policy associated with the incident.
  final String? policyName;

  /// The documentation associated with the incident.
  final String? documentation;

  /// The condition associated with the incident.
  final Condition? condition;

  /// The name of the condition associated with the incident.
  final String? conditionName;

  /// The threshold value of the incident.
  final String? thresholdValue;
}

/// {@template resource}
/// A resource associated with an incident.
/// {@endtemplate}
@JsonSerializable()
class Resource {
  /// {@macro resource}
  const Resource({this.type});

  /// Creates a [Resource] from a JSON [Map].
  factory Resource.fromJson(Map<String, dynamic> json) =>
      _$ResourceFromJson(json);

  /// Converts a [Resource] to the JSON representation.
  Map<String, dynamic> toJson() => _$ResourceToJson(this);

  /// The type of the resource.
  final String? type;
}

/// {@template metric}
/// A metric associated with an incident.
/// {@endtemplate}
@JsonSerializable()
class Metric {
  /// {@macro metric}
  const Metric({this.type, this.displayName});

  /// Creates a [Metric] from a JSON [Map].
  factory Metric.fromJson(Map<String, dynamic> json) => _$MetricFromJson(json);

  /// Converts a [Metric] to the JSON representation.
  Map<String, dynamic> toJson() => _$MetricToJson(this);

  /// The type of the metric.
  final String? type;

  /// The display name of the metric.
  final String? displayName;
}

/// {@template condition}
/// A condition associated with an incident.
/// {@endtemplate}
@JsonSerializable()
class Condition {
  /// {@macro condition}
  const Condition({this.name, this.displayName, this.conditionThreshold});

  /// Creates a [Condition] from a JSON [Map].
  factory Condition.fromJson(Map<String, dynamic> json) =>
      _$ConditionFromJson(json);

  /// Converts a [Condition] to the JSON representation.
  Map<String, dynamic> toJson() => _$ConditionToJson(this);

  /// The name of the condition.
  final String? name;

  /// The display name of the condition.
  final String? displayName;

  /// The condition threshold.
  final ConditionThreshold? conditionThreshold;
}

/// {@template condition_threshold}
/// The condition threshold associated with an incident.
/// {@endtemplate}
@JsonSerializable()
class ConditionThreshold {
  /// {@macro condition_threshold}
  const ConditionThreshold({
    this.filter,
    this.comparison,
    this.thresholdValue,
    this.duration,
    this.trigger,
  });

  /// Creates a [ConditionThreshold] from a JSON [Map].
  factory ConditionThreshold.fromJson(Map<String, dynamic> json) =>
      _$ConditionThresholdFromJson(json);

  /// Converts a [ConditionThreshold] to the JSON representation.
  Map<String, dynamic> toJson() => _$ConditionThresholdToJson(this);

  /// The filter associated with the condition threshold.
  final String? filter;

  /// The comparison associated with the condition threshold.
  final String? comparison;

  /// The threshold value associated with the condition threshold.
  final double? thresholdValue;

  /// The duration associated with the condition threshold.
  final String? duration;

  /// The trigger associated with the condition threshold.
  final Trigger? trigger;
}

/// {@template trigger}
/// The trigger associated with an incident.
/// {@endtemplate}
@JsonSerializable()
class Trigger {
  /// {@macro trigger}
  const Trigger({this.count});

  /// Creates a [Trigger] from a JSON [Map].
  factory Trigger.fromJson(Map<String, dynamic> json) =>
      _$TriggerFromJson(json);

  /// Converts a [Trigger] to the JSON representation.
  Map<String, dynamic> toJson() => _$TriggerToJson(this);

  /// The count associated with the trigger.
  final int? count;
}
