import 'package:json_annotation/json_annotation.dart';
import 'package:stripe_api/src/converters/converters.dart';

part 'stripe_meter_event_summary.g.dart';

/// {@template meter_event_summary}
/// A summary of meter events for a given time window.
/// {@endtemplate}
@JsonSerializable()
class StripeMeterEventSummary {
  /// {@macro meter_event_summary}
  StripeMeterEventSummary({
    required this.id,
    required this.aggregatedValue,
    required this.startTime,
    required this.endTime,
    required this.meterId,
  });

  /// Converts a `Map<String, dynamic>` to a [StripeMeterEventSummary].
  factory StripeMeterEventSummary.fromJson(Map<String, dynamic> json) =>
      _$StripeMeterEventSummaryFromJson(json);

  /// Converts a [StripeMeterEventSummary] to a `Map<String, dynamic>`.
  Map<String, dynamic> tojson() => _$StripeMeterEventSummaryToJson(this);

  /// The unique identifier for this object.
  final String id;

  /// The value of all events reported in this time window.
  final double aggregatedValue;

  /// The start of this summmarized time window.
  @TimestampConverter()
  final DateTime startTime;

  /// The end of this summmarized time window.
  @TimestampConverter()
  final DateTime endTime;

  /// The id of the event meter this object is summarizing.
  @JsonKey(name: 'meter')
  final String meterId;
}
