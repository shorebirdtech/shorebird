// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, unnecessary_lambdas

part of 'stripe_meter_event_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StripeMeterEventSummary _$StripeMeterEventSummaryFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'StripeMeterEventSummary',
  json,
  ($checkedConvert) {
    final val = StripeMeterEventSummary(
      id: $checkedConvert('id', (v) => v as String),
      aggregatedValue: $checkedConvert(
        'aggregated_value',
        (v) => (v as num).toDouble(),
      ),
      startTime: $checkedConvert(
        'start_time',
        (v) => const TimestampConverter().fromJson((v as num).toInt()),
      ),
      endTime: $checkedConvert(
        'end_time',
        (v) => const TimestampConverter().fromJson((v as num).toInt()),
      ),
      meterId: $checkedConvert('meter', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'aggregatedValue': 'aggregated_value',
    'startTime': 'start_time',
    'endTime': 'end_time',
    'meterId': 'meter',
  },
);

Map<String, dynamic> _$StripeMeterEventSummaryToJson(
  StripeMeterEventSummary instance,
) => <String, dynamic>{
  'id': instance.id,
  'aggregated_value': instance.aggregatedValue,
  'start_time': const TimestampConverter().toJson(instance.startTime),
  'end_time': const TimestampConverter().toJson(instance.endTime),
  'meter': instance.meterId,
};
