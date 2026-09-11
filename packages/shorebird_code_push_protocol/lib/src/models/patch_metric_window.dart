import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/metrics_range.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_metric_time_series_entry.dart';

/// {@template patch_metric_window}
/// One window of the patch-metric envelope: the summed count over the
/// window's effective range, with a per-bucket series when a `granularity`
/// was requested. This base atom is the full shape of `previous`;
/// `current` extends it (see PatchMetricCurrentWindow).
/// {@endtemplate}
@immutable
class PatchMetricWindow {
  /// {@macro patch_metric_window}
  const PatchMetricWindow({
    required this.count,
    required this.range,
    this.timeSeries,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchMetricWindow].
  factory PatchMetricWindow.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchMetricWindow',
      json,
      () => PatchMetricWindow(
        count: json['count'] as int,
        range: MetricsRange.fromJson(json['range'] as Map<String, dynamic>),
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
  static PatchMetricWindow? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchMetricWindow.fromJson(json);
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

  /// Converts a [PatchMetricWindow] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'count': count,
      'range': range.toJson(),
      'time_series': timeSeries?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    count,
    range,
    listHash(timeSeries),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchMetricWindow &&
        count == other.count &&
        range == other.range &&
        listsEqual(timeSeries, other.timeSeries);
  }
}
