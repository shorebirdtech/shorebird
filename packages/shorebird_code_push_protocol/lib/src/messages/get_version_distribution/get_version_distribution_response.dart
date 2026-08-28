import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/version_distribution_entry.dart';

/// {@template get_version_distribution_response}
/// The response body for GET /apps/{appId}/metrics/version-distribution.
/// {@endtemplate}
@immutable
class GetVersionDistributionResponse {
  /// {@macro get_version_distribution_response}
  const GetVersionDistributionResponse({
    required this.entries,
    required this.totalDevices,
    required this.activeWindowDays,
    required this.asOf,
  });

  /// Converts a `Map<String, dynamic>` to a [GetVersionDistributionResponse].
  factory GetVersionDistributionResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetVersionDistributionResponse',
      json,
      () => GetVersionDistributionResponse(
        entries: (json['entries'] as List)
            .map<VersionDistributionEntry>(
              (e) =>
                  VersionDistributionEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        totalDevices: json['total_devices'] as int,
        activeWindowDays: json['active_window_days'] as int,
        asOf: DateTime.parse(json['as_of'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetVersionDistributionResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetVersionDistributionResponse.fromJson(json);
  }

  /// One entry per release version, sorted by `device_count`
  /// descending, then `release_version` ascending with NULLs last.
  final List<VersionDistributionEntry> entries;

  /// Sum of `device_count` across all entries. Convenience for
  /// clients; matches the server-side sum used to compute
  /// `percentage`.
  final int totalDevices;

  /// The active-device window in days that bounds the query.
  /// Hardcoded server-side in v1; tier-gated per-caller windows
  /// land in a follow-up.
  final int activeWindowDays;

  /// Server's UTC timestamp at the moment the response was
  /// constructed. Not a freshness indicator for the underlying
  /// data, which is refreshed by an hourly scheduled query and
  /// may lag by up to ~1 hour.
  final DateTime asOf;

  /// Converts a [GetVersionDistributionResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'entries': entries.map((e) => e.toJson()).toList(),
      'total_devices': totalDevices,
      'active_window_days': activeWindowDays,
      'as_of': asOf.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(entries),
    totalDevices,
    activeWindowDays,
    asOf,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetVersionDistributionResponse &&
        listsEqual(entries, other.entries) &&
        totalDevices == other.totalDevices &&
        activeWindowDays == other.activeWindowDays &&
        asOf == other.asOf;
  }
}
