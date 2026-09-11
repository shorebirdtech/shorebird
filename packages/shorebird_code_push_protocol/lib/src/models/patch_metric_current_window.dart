import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/metrics_range.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_metric_breakdown_entry.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_metric_time_series_entry.dart';

/// {@template patch_metric_current_window}
/// The `current` window of the patch-metric envelope: the base window atom
/// plus the optional `breakdown`. Only `current` carries a breakdown — no
/// chart renders a previous-window breakdown, so the asymmetry is declared
/// in the contract rather than left as an optional-but-never-populated
/// field.
/// {@endtemplate}
@immutable
class PatchMetricCurrentWindow {
  /// {@macro patch_metric_current_window}
  const PatchMetricCurrentWindow({
    required this.count,
    required this.range,
    this.timeSeries,
    this.breakdown,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchMetricCurrentWindow].
  factory PatchMetricCurrentWindow.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchMetricCurrentWindow',
      json,
      () => PatchMetricCurrentWindow(
        count: json['count'] as int,
        range: MetricsRange.fromJson(json['range'] as Map<String, dynamic>),
        timeSeries: (json['time_series'] as List?)
            ?.map<PatchMetricTimeSeriesEntry>(
              (e) => PatchMetricTimeSeriesEntry.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
        breakdown: (json['breakdown'] as List?)
            ?.map<PatchMetricBreakdownEntry>(
              (e) =>
                  PatchMetricBreakdownEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchMetricCurrentWindow? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchMetricCurrentWindow.fromJson(json);
  }

  /// The summed count (installs or downloads) over this window. Unlike
  /// the HLL-based metrics, per-bucket `time_series` values sum to this
  /// total.
  final int count;

  /// The effective (post-default, post-clamp) window a metrics response —
  /// or one window of a metrics envelope — covers. Always echoed by the
  /// server; clients must treat it as authoritative rather than reusing
  /// the requested range.
  final MetricsRange range;

  /// Per-bucket series for this window, present only when a
  /// `granularity` was requested; otherwise null. On `previous`, also
  /// null when the prior window reaches past the plan's metrics-history
  /// horizon (the total is still present — only the granular overlay is
  /// withheld). Empty buckets are omitted — gap-fill against this
  /// window's `range`.
  final List<PatchMetricTimeSeriesEntry>? timeSeries;

  /// Per-group counts for this window, present only when a
  /// `group_by` was requested; otherwise null.
  final List<PatchMetricBreakdownEntry>? breakdown;

  /// Converts a [PatchMetricCurrentWindow] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'count': count,
      'range': range.toJson(),
      'time_series': timeSeries?.map((e) => e.toJson()).toList(),
      'breakdown': breakdown?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    count,
    range,
    listHash(timeSeries),
    listHash(breakdown),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchMetricCurrentWindow &&
        count == other.count &&
        range == other.range &&
        listsEqual(timeSeries, other.timeSeries) &&
        listsEqual(breakdown, other.breakdown);
  }
}
