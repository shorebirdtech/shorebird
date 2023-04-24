// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'gcp_alert.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GCPAlert _$GCPAlertFromJson(Map<String, dynamic> json) => $checkedCreate(
      'GCPAlert',
      json,
      ($checkedConvert) {
        final val = GCPAlert(
          version: $checkedConvert('version', (v) => v as String?),
          incident: $checkedConvert(
              'incident',
              (v) => v == null
                  ? null
                  : Incident.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );

Map<String, dynamic> _$GCPAlertToJson(GCPAlert instance) => <String, dynamic>{
      'version': instance.version,
      'incident': instance.incident?.toJson(),
    };

Incident _$IncidentFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Incident',
      json,
      ($checkedConvert) {
        final val = Incident(
          incidentId: $checkedConvert('incident_id', (v) => v as String?),
          scopingProjectId:
              $checkedConvert('scoping_project_id', (v) => v as String?),
          scopingProjectNumber:
              $checkedConvert('scoping_project_number', (v) => v as int?),
          url: $checkedConvert('url', (v) => v as String?),
          startedAt: $checkedConvert('started_at', (v) => v as int?),
          endedAt: $checkedConvert('ended_at', (v) => v as int?),
          state: $checkedConvert('state', (v) => v as String?),
          summary: $checkedConvert('summary', (v) => v as String?),
          observedValue: $checkedConvert('observed_value', (v) => v as String?),
          resource: $checkedConvert(
              'resource',
              (v) => v == null
                  ? null
                  : Resource.fromJson(v as Map<String, dynamic>)),
          resourceTypeDisplayName: $checkedConvert(
              'resource_type_display_name', (v) => v as String?),
          resourceId: $checkedConvert('resource_id', (v) => v as String?),
          resourceDisplayName:
              $checkedConvert('resource_display_name', (v) => v as String?),
          resourceName: $checkedConvert('resource_name', (v) => v as String?),
          metric: $checkedConvert(
              'metric',
              (v) => v == null
                  ? null
                  : Metric.fromJson(v as Map<String, dynamic>)),
          policyName: $checkedConvert('policy_name', (v) => v as String?),
          documentation: $checkedConvert('documentation', (v) => v as String?),
          condition: $checkedConvert(
              'condition',
              (v) => v == null
                  ? null
                  : Condition.fromJson(v as Map<String, dynamic>)),
          conditionName: $checkedConvert('condition_name', (v) => v as String?),
          thresholdValue:
              $checkedConvert('threshold_value', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'incidentId': 'incident_id',
        'scopingProjectId': 'scoping_project_id',
        'scopingProjectNumber': 'scoping_project_number',
        'startedAt': 'started_at',
        'endedAt': 'ended_at',
        'observedValue': 'observed_value',
        'resourceTypeDisplayName': 'resource_type_display_name',
        'resourceId': 'resource_id',
        'resourceDisplayName': 'resource_display_name',
        'resourceName': 'resource_name',
        'policyName': 'policy_name',
        'conditionName': 'condition_name',
        'thresholdValue': 'threshold_value'
      },
    );

Map<String, dynamic> _$IncidentToJson(Incident instance) => <String, dynamic>{
      'incident_id': instance.incidentId,
      'scoping_project_id': instance.scopingProjectId,
      'scoping_project_number': instance.scopingProjectNumber,
      'url': instance.url,
      'started_at': instance.startedAt,
      'ended_at': instance.endedAt,
      'state': instance.state,
      'summary': instance.summary,
      'observed_value': instance.observedValue,
      'resource': instance.resource?.toJson(),
      'resource_type_display_name': instance.resourceTypeDisplayName,
      'resource_id': instance.resourceId,
      'resource_display_name': instance.resourceDisplayName,
      'resource_name': instance.resourceName,
      'metric': instance.metric?.toJson(),
      'policy_name': instance.policyName,
      'documentation': instance.documentation,
      'condition': instance.condition?.toJson(),
      'condition_name': instance.conditionName,
      'threshold_value': instance.thresholdValue,
    };

Resource _$ResourceFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Resource',
      json,
      ($checkedConvert) {
        final val = Resource(
          type: $checkedConvert('type', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$ResourceToJson(Resource instance) => <String, dynamic>{
      'type': instance.type,
    };

Metric _$MetricFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Metric',
      json,
      ($checkedConvert) {
        final val = Metric(
          type: $checkedConvert('type', (v) => v as String?),
          displayName: $checkedConvert('display_name', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {'displayName': 'display_name'},
    );

Map<String, dynamic> _$MetricToJson(Metric instance) => <String, dynamic>{
      'type': instance.type,
      'display_name': instance.displayName,
    };

Condition _$ConditionFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Condition',
      json,
      ($checkedConvert) {
        final val = Condition(
          name: $checkedConvert('name', (v) => v as String?),
          displayName: $checkedConvert('display_name', (v) => v as String?),
          conditionThreshold: $checkedConvert(
              'condition_threshold',
              (v) => v == null
                  ? null
                  : ConditionThreshold.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {
        'displayName': 'display_name',
        'conditionThreshold': 'condition_threshold'
      },
    );

Map<String, dynamic> _$ConditionToJson(Condition instance) => <String, dynamic>{
      'name': instance.name,
      'display_name': instance.displayName,
      'condition_threshold': instance.conditionThreshold?.toJson(),
    };

ConditionThreshold _$ConditionThresholdFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ConditionThreshold',
      json,
      ($checkedConvert) {
        final val = ConditionThreshold(
          filter: $checkedConvert('filter', (v) => v as String?),
          comparison: $checkedConvert('comparison', (v) => v as String?),
          thresholdValue: $checkedConvert(
              'threshold_value', (v) => (v as num?)?.toDouble()),
          duration: $checkedConvert('duration', (v) => v as String?),
          trigger: $checkedConvert(
              'trigger',
              (v) => v == null
                  ? null
                  : Trigger.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {'thresholdValue': 'threshold_value'},
    );

Map<String, dynamic> _$ConditionThresholdToJson(ConditionThreshold instance) =>
    <String, dynamic>{
      'filter': instance.filter,
      'comparison': instance.comparison,
      'threshold_value': instance.thresholdValue,
      'duration': instance.duration,
      'trigger': instance.trigger?.toJson(),
    };

Trigger _$TriggerFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Trigger',
      json,
      ($checkedConvert) {
        final val = Trigger(
          count: $checkedConvert('count', (v) => v as int?),
        );
        return val;
      },
    );

Map<String, dynamic> _$TriggerToJson(Trigger instance) => <String, dynamic>{
      'count': instance.count,
    };
