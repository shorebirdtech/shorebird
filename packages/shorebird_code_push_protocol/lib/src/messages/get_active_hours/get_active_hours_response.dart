import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/active_hour_entry.dart';

/// {@template get_active_hours_response}
/// The response body for GET /apps/{appId}/metrics/active-hours. Powers the
/// "best time to release" recommendation: the consecutive low-activity UTC
/// window when the app's users are least active.
/// {@endtemplate}
@immutable
class GetActiveHoursResponse {
  /// {@macro get_active_hours_response}
  const GetActiveHoursResponse({
    required this.hourly,
    required this.recommendedWindowStartUtc,
    required this.recommendedWindowLengthHours,
    required this.busiestHourUtc,
    required this.lookbackDays,
    required this.asOf,
  });

  /// Converts a `Map<String, dynamic>` to a [GetActiveHoursResponse].
  factory GetActiveHoursResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetActiveHoursResponse',
      json,
      () => GetActiveHoursResponse(
        hourly: (json['hourly'] as List)
            .map<ActiveHourEntry>(
              (e) => ActiveHourEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        recommendedWindowStartUtc:
            checkedKey(json, 'recommended_window_start_utc') as int?,
        recommendedWindowLengthHours:
            json['recommended_window_length_hours'] as int,
        busiestHourUtc: checkedKey(json, 'busiest_hour_utc') as int?,
        lookbackDays: json['lookback_days'] as int,
        asOf: DateTime.parse(json['as_of'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetActiveHoursResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetActiveHoursResponse.fromJson(json);
  }

  /// One entry per UTC hour: 24 entries, hour_utc 0–23, zero-filled,
  /// ordered by hour_utc ascending.
  final List<ActiveHourEntry> hourly;

  /// Start hour (UTC, 0–23) of the lowest-activity consecutive window —
  /// the recommended time to release. The window wraps past midnight.
  /// Null when there is insufficient data (fewer than 7 days).
  final int? recommendedWindowStartUtc;

  /// Length of the recommended window in hours. Fixed at 2 in v1.
  final int recommendedWindowLengthHours;

  /// UTC hour (0–23) with the highest average active devices, for
  /// contrast in the recommendation copy. Null when insufficient data.
  final int? busiestHourUtc;

  /// Number of days of history the profile is computed over.
  final int lookbackDays;

  /// Server's UTC timestamp at the moment the response was constructed.
  /// Not a freshness indicator for the underlying data, which is
  /// refreshed by an hourly scheduled query and may lag by up to ~1 hour.
  final DateTime asOf;

  /// Converts a [GetActiveHoursResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'hourly': hourly.map((e) => e.toJson()).toList(),
      'recommended_window_start_utc': recommendedWindowStartUtc,
      'recommended_window_length_hours': recommendedWindowLengthHours,
      'busiest_hour_utc': busiestHourUtc,
      'lookback_days': lookbackDays,
      'as_of': asOf.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(hourly),
    recommendedWindowStartUtc,
    recommendedWindowLengthHours,
    busiestHourUtc,
    lookbackDays,
    asOf,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetActiveHoursResponse &&
        listsEqual(hourly, other.hourly) &&
        recommendedWindowStartUtc == other.recommendedWindowStartUtc &&
        recommendedWindowLengthHours == other.recommendedWindowLengthHours &&
        busiestHourUtc == other.busiestHourUtc &&
        lookbackDays == other.lookbackDays &&
        asOf == other.asOf;
  }
}
