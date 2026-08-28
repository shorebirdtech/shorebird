import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template patch_metric_time_series_entry}
/// One bucket of a patch-metric time series: the summed count (installs or
/// downloads, per the endpoint) in the bucket starting at `period`.
/// {@endtemplate}
@immutable
class PatchMetricTimeSeriesEntry {
  /// {@macro patch_metric_time_series_entry}
  const PatchMetricTimeSeriesEntry({
    required this.period,
    required this.count,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchMetricTimeSeriesEntry].
  factory PatchMetricTimeSeriesEntry.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchMetricTimeSeriesEntry',
      json,
      () => PatchMetricTimeSeriesEntry(
        period: DateTime.parse(json['period'] as String),
        count: json['count'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchMetricTimeSeriesEntry? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchMetricTimeSeriesEntry.fromJson(json);
  }

  /// The bucket start (UTC).
  final DateTime period;

  /// The summed count in this bucket.
  final int count;

  /// Converts a [PatchMetricTimeSeriesEntry] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'period': period.toIso8601String(),
      'count': count,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    period,
    count,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchMetricTimeSeriesEntry &&
        period == other.period &&
        count == other.count;
  }
}
