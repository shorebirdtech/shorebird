import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template activity_heatmap_cell}
/// Average number of distinct active devices during one (UTC day-of-week,
/// UTC hour-of-day) cell, averaged across every occurrence of that weekday
/// in the lookback window (occurrences with no activity count as zero).
/// {@endtemplate}
@immutable
class ActivityHeatmapCell {
  /// {@macro activity_heatmap_cell}
  const ActivityHeatmapCell({
    required this.dayOfWeekUtc,
    required this.hourUtc,
    required this.averageActiveDevices,
  });

  /// Converts a `Map<String, dynamic>` to an [ActivityHeatmapCell].
  factory ActivityHeatmapCell.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ActivityHeatmapCell',
      json,
      () => ActivityHeatmapCell(
        dayOfWeekUtc: json['day_of_week_utc'] as int,
        hourUtc: json['hour_utc'] as int,
        averageActiveDevices: (json['average_active_devices'] as num)
            .toDouble(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ActivityHeatmapCell? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ActivityHeatmapCell.fromJson(json);
  }

  /// Day of week in UTC, 1–7 where 1 = Sunday and 7 = Saturday.
  final int dayOfWeekUtc;

  /// Hour of day in UTC, 0–23.
  final int hourUtc;

  /// Mean distinct active devices seen during this UTC weekday-hour,
  /// averaged over the weekday's occurrences in the window with implicit
  /// zeros included.
  final double averageActiveDevices;

  /// Converts an [ActivityHeatmapCell] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'day_of_week_utc': dayOfWeekUtc,
      'hour_utc': hourUtc,
      'average_active_devices': averageActiveDevices,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    dayOfWeekUtc,
    hourUtc,
    averageActiveDevices,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActivityHeatmapCell &&
        dayOfWeekUtc == other.dayOfWeekUtc &&
        hourUtc == other.hourUtc &&
        averageActiveDevices == other.averageActiveDevices;
  }
}
