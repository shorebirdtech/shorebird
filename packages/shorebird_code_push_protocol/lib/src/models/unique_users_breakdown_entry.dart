import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/unique_users_time_series_entry.dart';

/// {@template unique_users_breakdown_entry}
/// Unique users for one value of the `group_by` dimension (e.g. one
/// platform), optionally with its own time series.
/// {@endtemplate}
@immutable
class UniqueUsersBreakdownEntry {
  /// {@macro unique_users_breakdown_entry}
  const UniqueUsersBreakdownEntry({
    required this.groupBy,
    required this.groupValue,
    required this.uniqueUsers,
    this.timeSeries,
  });

  /// Converts a `Map<String, dynamic>` to a [UniqueUsersBreakdownEntry].
  factory UniqueUsersBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UniqueUsersBreakdownEntry',
      json,
      () => UniqueUsersBreakdownEntry(
        groupBy: json['group_by'] as String,
        groupValue: json['group_value'] as String,
        uniqueUsers: json['unique_users'] as int,
        timeSeries: (json['time_series'] as List?)
            ?.map<UniqueUsersTimeSeriesEntry>(
              (e) => UniqueUsersTimeSeriesEntry.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UniqueUsersBreakdownEntry? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UniqueUsersBreakdownEntry.fromJson(json);
  }

  /// The dimension this entry breaks down by (e.g. "platform").
  final String groupBy;

  /// The value within `group_by` (e.g. "android"). For
  /// `group_by=release_version`, the empty string is the
  /// unknown-version group — devices whose client is too old to
  /// report a release version.
  final String groupValue;

  /// Distinct active devices for this group over the window (an HLL
  /// count).
  final int uniqueUsers;

  /// Per-bucket series for this group, present only when a `granularity`
  /// was requested; otherwise null.
  final List<UniqueUsersTimeSeriesEntry>? timeSeries;

  /// Converts a [UniqueUsersBreakdownEntry] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'group_by': groupBy,
      'group_value': groupValue,
      'unique_users': uniqueUsers,
      'time_series': timeSeries?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    groupBy,
    groupValue,
    uniqueUsers,
    listHash(timeSeries),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UniqueUsersBreakdownEntry &&
        groupBy == other.groupBy &&
        groupValue == other.groupValue &&
        uniqueUsers == other.uniqueUsers &&
        listsEqual(timeSeries, other.timeSeries);
  }
}
