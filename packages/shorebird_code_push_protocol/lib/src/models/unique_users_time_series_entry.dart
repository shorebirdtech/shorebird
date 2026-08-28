import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template unique_users_time_series_entry}
/// One bucket of a unique-users time series: the HLL count of distinct
/// active devices in the bucket starting at `period`.
/// {@endtemplate}
@immutable
class UniqueUsersTimeSeriesEntry {
  /// {@macro unique_users_time_series_entry}
  const UniqueUsersTimeSeriesEntry({
    required this.period,
    required this.uniqueUsers,
  });

  /// Converts a `Map<String, dynamic>` to a [UniqueUsersTimeSeriesEntry].
  factory UniqueUsersTimeSeriesEntry.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UniqueUsersTimeSeriesEntry',
      json,
      () => UniqueUsersTimeSeriesEntry(
        period: DateTime.parse(json['period'] as String),
        uniqueUsers: json['unique_users'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UniqueUsersTimeSeriesEntry? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UniqueUsersTimeSeriesEntry.fromJson(json);
  }

  /// The bucket start (UTC).
  final DateTime period;

  /// Distinct active devices in this bucket (an HLL count).
  final int uniqueUsers;

  /// Converts a [UniqueUsersTimeSeriesEntry] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'period': period.toIso8601String(),
      'unique_users': uniqueUsers,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    period,
    uniqueUsers,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UniqueUsersTimeSeriesEntry &&
        period == other.period &&
        uniqueUsers == other.uniqueUsers;
  }
}
