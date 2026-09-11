import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template active_hour_entry}
/// Average number of distinct active devices during one UTC hour-of-day,
/// averaged across all days in the lookback window (days with no activity
/// in that hour count as zero).
/// {@endtemplate}
@immutable
class ActiveHourEntry {
  /// {@macro active_hour_entry}
  const ActiveHourEntry({
    required this.hourUtc,
    required this.averageActiveDevices,
  });

  /// Converts a `Map<String, dynamic>` to an [ActiveHourEntry].
  factory ActiveHourEntry.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ActiveHourEntry',
      json,
      () => ActiveHourEntry(
        hourUtc: json['hour_utc'] as int,
        averageActiveDevices: (json['average_active_devices'] as num)
            .toDouble(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ActiveHourEntry? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ActiveHourEntry.fromJson(json);
  }

  /// Hour of day in UTC, 0–23.
  final int hourUtc;

  /// Mean distinct active devices seen during this UTC hour, averaged
  /// over the lookback window with implicit zeros included.
  final double averageActiveDevices;

  /// Converts an [ActiveHourEntry] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'hour_utc': hourUtc,
      'average_active_devices': averageActiveDevices,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    hourUtc,
    averageActiveDevices,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActiveHourEntry &&
        hourUtc == other.hourUtc &&
        averageActiveDevices == other.averageActiveDevices;
  }
}
