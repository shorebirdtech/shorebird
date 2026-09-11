import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/activity_heatmap_cell.dart';

/// {@template get_activity_heatmap_response}
/// The response body for GET /apps/{appId}/metrics/activity-heatmap. A 7×24
/// grid of average active devices per UTC weekday-hour, powering the
/// insights activity heatmap.
/// {@endtemplate}
@immutable
class GetActivityHeatmapResponse {
  /// {@macro get_activity_heatmap_response}
  const GetActivityHeatmapResponse({
    required this.cells,
    required this.busiestDayOfWeekUtc,
    required this.busiestHourUtc,
    required this.lookbackDays,
    required this.asOf,
  });

  /// Converts a `Map<String, dynamic>` to a [GetActivityHeatmapResponse].
  factory GetActivityHeatmapResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetActivityHeatmapResponse',
      json,
      () => GetActivityHeatmapResponse(
        cells: (json['cells'] as List)
            .map<ActivityHeatmapCell>(
              (e) => ActivityHeatmapCell.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        busiestDayOfWeekUtc:
            checkedKey(json, 'busiest_day_of_week_utc') as int?,
        busiestHourUtc: checkedKey(json, 'busiest_hour_utc') as int?,
        lookbackDays: json['lookback_days'] as int,
        asOf: DateTime.parse(json['as_of'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetActivityHeatmapResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetActivityHeatmapResponse.fromJson(json);
  }

  /// 168 entries (7 weekdays × 24 hours), zero-filled, ordered by
  /// day_of_week_utc (1–7) then hour_utc (0–23) ascending.
  final List<ActivityHeatmapCell> cells;

  /// UTC day-of-week (1–7) of the cell with the highest average active
  /// devices, for peak-relative coloring and labeling. Null when there is
  /// no data.
  final int? busiestDayOfWeekUtc;

  /// UTC hour (0–23) of the busiest cell. Null when there is no data.
  final int? busiestHourUtc;

  /// Number of days of history the heatmap is computed over.
  final int lookbackDays;

  /// Server's UTC timestamp at the moment the response was constructed.
  /// Not a freshness indicator for the underlying data, which is
  /// refreshed by an hourly scheduled query and may lag by up to ~1 hour.
  final DateTime asOf;

  /// Converts a [GetActivityHeatmapResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'cells': cells.map((e) => e.toJson()).toList(),
      'busiest_day_of_week_utc': busiestDayOfWeekUtc,
      'busiest_hour_utc': busiestHourUtc,
      'lookback_days': lookbackDays,
      'as_of': asOf.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(cells),
    busiestDayOfWeekUtc,
    busiestHourUtc,
    lookbackDays,
    asOf,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetActivityHeatmapResponse &&
        listsEqual(cells, other.cells) &&
        busiestDayOfWeekUtc == other.busiestDayOfWeekUtc &&
        busiestHourUtc == other.busiestHourUtc &&
        lookbackDays == other.lookbackDays &&
        asOf == other.asOf;
  }
}
