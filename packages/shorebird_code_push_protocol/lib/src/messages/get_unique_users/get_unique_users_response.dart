import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/unique_users_breakdown_entry.dart';
import 'package:shorebird_code_push_protocol/src/models/unique_users_range.dart';
import 'package:shorebird_code_push_protocol/src/models/unique_users_time_series_entry.dart';

/// {@template get_unique_users_response}
/// The response body for GET /apps/{appId}/metrics/unique-users.
/// {@endtemplate}
@immutable
class GetUniqueUsersResponse {
  /// {@macro get_unique_users_response}
  const GetUniqueUsersResponse({
    required this.uniqueUsers,
    required this.granularity,
    required this.range,
    required this.asOf,
    this.timeSeries,
    this.breakdown,
  });

  /// Converts a `Map<String, dynamic>` to a [GetUniqueUsersResponse].
  factory GetUniqueUsersResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetUniqueUsersResponse',
      json,
      () => GetUniqueUsersResponse(
        uniqueUsers: json['unique_users'] as int,
        granularity: checkedKey(json, 'granularity') as String?,
        range: UniqueUsersRange.fromJson(json['range'] as Map<String, dynamic>),
        asOf: DateTime.parse(json['as_of'] as String),
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
  static GetUniqueUsersResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetUniqueUsersResponse.fromJson(json);
  }

  /// Distinct active devices over the whole window (an HLL count).
  final int uniqueUsers;

  /// The time-series bucket resolution (`hour`, `day`, `week`, or
  /// `month`), or null when no time series was requested.
  final String? granularity;

  /// The window the unique-users response covers.
  final UniqueUsersRange range;

  /// Server's UTC timestamp at the moment the response was constructed.
  /// Not a freshness indicator for the underlying data, which is
  /// refreshed by an hourly scheduled query and may lag by up to ~1 hour.
  final DateTime asOf;

  /// The top-level time series, present only when a `granularity` was
  /// requested; otherwise null.
  final List<UniqueUsersTimeSeriesEntry>? timeSeries;

  /// Per-group unique users, present only when a `group_by` was
  /// requested; otherwise null.
  final List<UniqueUsersBreakdownEntry>? breakdown;

  /// Converts a [GetUniqueUsersResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'unique_users': uniqueUsers,
      'granularity': granularity,
      'range': range.toJson(),
      'as_of': asOf.toIso8601String(),
      'time_series': timeSeries?.map((e) => e.toJson()).toList(),
      'breakdown': breakdown?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    uniqueUsers,
    granularity,
    range,
    asOf,
    listHash(timeSeries),
    listHash(breakdown),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetUniqueUsersResponse &&
        uniqueUsers == other.uniqueUsers &&
        granularity == other.granularity &&
        range == other.range &&
        asOf == other.asOf &&
        listsEqual(timeSeries, other.timeSeries) &&
        listsEqual(breakdown, other.breakdown);
  }
}
