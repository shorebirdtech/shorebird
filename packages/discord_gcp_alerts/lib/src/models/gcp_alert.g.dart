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
          incident: $checkedConvert(
              'incident',
              (v) => v == null
                  ? null
                  : Incident.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );

Incident _$IncidentFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Incident',
      json,
      ($checkedConvert) {
        final val = Incident(
          url: $checkedConvert('url', (v) => v as String?),
          state: $checkedConvert('state', (v) => v as String?),
          summary: $checkedConvert('summary', (v) => v as String?),
          resourceName: $checkedConvert('resource_name', (v) => v as String?),
          conditionName: $checkedConvert('condition_name', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'resourceName': 'resource_name',
        'conditionName': 'condition_name'
      },
    );
