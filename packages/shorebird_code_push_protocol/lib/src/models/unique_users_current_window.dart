import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/metrics_range.dart';
import 'package:shorebird_code_push_protocol/src/models/unique_users_breakdown_entry.dart';
import 'package:shorebird_code_push_protocol/src/models/unique_users_time_series_entry.dart';

/// {@template unique_users_current_window}
/// The `current` window of the unique-users envelope: the base window
/// atom plus the optional `breakdown`. Only `current` carries a
/// breakdown — no chart renders a previous-window breakdown, so the
/// asymmetry is declared in the contract rather than left as an
/// optional-but-never-populated field.
/// {@endtemplate}
@immutable
class UniqueUsersCurrentWindow {
  /// {@macro unique_users_current_window}
  const UniqueUsersCurrentWindow({
    required this.uniqueUsers,
    required this.range,
    this.timeSeries,
    this.breakdown,
  });

  /// Converts a `Map<String, dynamic>` to a [UniqueUsersCurrentWindow].
  factory UniqueUsersCurrentWindow.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UniqueUsersCurrentWindow',
      json,
      () => UniqueUsersCurrentWindow(
        uniqueUsers: json['unique_users'] as int,
        range: MetricsRange.fromJson(json['range'] as Map<String, dynamic>),
        timeSeries: (json['time_series'] as List?)
            ?.map<UniqueUsersTimeSeriesEntry>(
              (e) => UniqueUsersTimeSeriesEntry.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
        breakdown: (json['breakdown'] as List?)
            ?.map<UniqueUsersBreakdownEntry>(
              (e) =>
                  UniqueUsersBreakdownEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UniqueUsersCurrentWindow? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UniqueUsersCurrentWindow.fromJson(json);
  }

  /// Distinct active devices over this window (an HLL count). Note:
  /// per-bucket `time_series` values do not sum to this — an HLL merge
  /// over the window is not a sum of per-bucket merges.
  final int uniqueUsers;

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
  final List<UniqueUsersTimeSeriesEntry>? timeSeries;

  /// Per-group unique users for this window, present only when a
  /// `group_by` was requested; otherwise null.
  final List<UniqueUsersBreakdownEntry>? breakdown;

  /// Converts a [UniqueUsersCurrentWindow] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'unique_users': uniqueUsers,
      'range': range.toJson(),
      'time_series': timeSeries?.map((e) => e.toJson()).toList(),
      'breakdown': breakdown?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    uniqueUsers,
    range,
    listHash(timeSeries),
    listHash(breakdown),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UniqueUsersCurrentWindow &&
        uniqueUsers == other.uniqueUsers &&
        range == other.range &&
        listsEqual(timeSeries, other.timeSeries) &&
        listsEqual(breakdown, other.breakdown);
  }
}
