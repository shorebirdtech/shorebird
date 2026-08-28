import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template get_new_devices_response}
/// The response body for GET /apps/{appId}/metrics/new-devices.
/// {@endtemplate}
@immutable
class GetNewDevicesResponse {
  /// {@macro get_new_devices_response}
  const GetNewDevicesResponse({
    required this.current,
    required this.previous,
    required this.windowDays,
    required this.asOf,
  });

  /// Converts a `Map<String, dynamic>` to a [GetNewDevicesResponse].
  factory GetNewDevicesResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetNewDevicesResponse',
      json,
      () => GetNewDevicesResponse(
        current: json['current'] as int,
        previous: checkedKey(json, 'previous') as int?,
        windowDays: json['window_days'] as int,
        asOf: DateTime.parse(json['as_of'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetNewDevicesResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetNewDevicesResponse.fromJson(json);
  }

  /// Devices first seen in the window `[as_of − window_days, as_of)`.
  /// An exact (non-HLL) count.
  final int current;

  /// Devices first seen in the equal-length window immediately
  /// preceding the current one, or null when that window would begin
  /// before the metrics data floor (comparing against
  /// partially-recorded history would show a misleading delta).
  final int? previous;

  /// The window length in days. Hardcoded server-side in v1; echoed
  /// so clients label the metric from the response rather than
  /// assuming a length.
  final int windowDays;

  /// Server's UTC timestamp at the moment the response was
  /// constructed. Not a freshness indicator for the underlying
  /// data, which is refreshed by an hourly scheduled query and
  /// may lag by up to ~1 hour.
  final DateTime asOf;

  /// Converts a [GetNewDevicesResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'current': current,
      'previous': previous,
      'window_days': windowDays,
      'as_of': asOf.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    current,
    previous,
    windowDays,
    asOf,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetNewDevicesResponse &&
        current == other.current &&
        previous == other.previous &&
        windowDays == other.windowDays &&
        asOf == other.asOf;
  }
}
