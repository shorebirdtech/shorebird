import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_metric_time_series_entry.dart';

/// {@template patch_metric_breakdown_entry}
/// A patch metric for one value of the `group_by` dimension (one release
/// at app scope, or one patch at release scope), optionally with its own
/// time series.
/// {@endtemplate}
@immutable
class PatchMetricBreakdownEntry {
  /// {@macro patch_metric_breakdown_entry}
  const PatchMetricBreakdownEntry({
    required this.groupBy,
    required this.groupValue,
    required this.count,
    this.timeSeries,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchMetricBreakdownEntry].
  factory PatchMetricBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchMetricBreakdownEntry',
      json,
      () => PatchMetricBreakdownEntry(
        groupBy: json['group_by'] as String,
        groupValue: json['group_value'] as String,
        count: json['count'] as int,
        timeSeries: (json['time_series'] as List?)
            ?.map<PatchMetricTimeSeriesEntry>(
              (e) => PatchMetricTimeSeriesEntry.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchMetricBreakdownEntry? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchMetricBreakdownEntry.fromJson(json);
  }

  /// The dimension this entry breaks down by ("release" or "patch").
  final String groupBy;

  /// The value within `group_by`: the release version, or the patch
  /// number as a string.
  final String groupValue;

  /// The summed count for this group over the window.
  final int count;

  /// Per-bucket series for this group, present only when a `granularity`
  /// was requested; otherwise null.
  final List<PatchMetricTimeSeriesEntry>? timeSeries;

  /// Converts a [PatchMetricBreakdownEntry] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'group_by': groupBy,
      'group_value': groupValue,
      'count': count,
      'time_series': timeSeries?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    groupBy,
    groupValue,
    count,
    listHash(timeSeries),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchMetricBreakdownEntry &&
        groupBy == other.groupBy &&
        groupValue == other.groupValue &&
        count == other.count &&
        listsEqual(timeSeries, other.timeSeries);
  }
}
