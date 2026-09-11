import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_metric_current_window.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_metric_window.dart';

/// {@template get_patch_metric_response}
/// The response body for the patch-installs and patch-downloads metric
/// endpoints (app- and release-scoped): a current/previous envelope.
/// `previous` covers the equal-length window immediately preceding
/// `current`; period-over-period deltas are client display logic over the
/// two totals. `previous` is omitted only when the prior window predates
/// the data floor (no comparison data exists). When it reaches past the
/// plan's metrics-history horizon, `previous` is still present with its
/// total — the delta renders — but without a `time_series` (no
/// prior-window overlay): granular history is the resolution the horizon
/// gates, the scalar comparison is not.
/// {@endtemplate}
@immutable
class GetPatchMetricResponse {
  /// {@macro get_patch_metric_response}
  const GetPatchMetricResponse({
    required this.asOf,
    required this.granularity,
    required this.current,
    this.previous,
  });

  /// Converts a `Map<String, dynamic>` to a [GetPatchMetricResponse].
  factory GetPatchMetricResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetPatchMetricResponse',
      json,
      () => GetPatchMetricResponse(
        asOf: DateTime.parse(json['as_of'] as String),
        granularity: checkedKey(json, 'granularity') as String?,
        current: PatchMetricCurrentWindow.fromJson(
          json['current'] as Map<String, dynamic>,
        ),
        previous: PatchMetricWindow.maybeFromJson(
          json['previous'] as Map<String, dynamic>?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetPatchMetricResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetPatchMetricResponse.fromJson(json);
  }

  /// Server's UTC timestamp at the moment the response was constructed.
  /// Not a freshness indicator for the underlying data, which is
  /// refreshed by an hourly scheduled job and may lag by up to ~1 hour.
  final DateTime asOf;

  /// The time-series bucket resolution (`hour`, `day`, or `week`), or
  /// null when no time series was requested. Applies to both windows.
  final String? granularity;

  /// The `current` window of the patch-metric envelope: the base window atom
  /// plus the optional `breakdown`. Only `current` carries a breakdown — no
  /// chart renders a previous-window breakdown, so the asymmetry is declared
  /// in the contract rather than left as an optional-but-never-populated
  /// field.
  final PatchMetricCurrentWindow current;

  /// One window of the patch-metric envelope: the summed count over the
  /// window's effective range, with a per-bucket series when a `granularity`
  /// was requested. This base atom is the full shape of `previous`;
  /// `current` extends it (see PatchMetricCurrentWindow).
  final PatchMetricWindow? previous;

  /// Converts a [GetPatchMetricResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'as_of': asOf.toIso8601String(),
      'granularity': granularity,
      'current': current.toJson(),
      'previous': previous?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    asOf,
    granularity,
    current,
    previous,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetPatchMetricResponse &&
        asOf == other.asOf &&
        granularity == other.granularity &&
        current == other.current &&
        previous == other.previous;
  }
}
