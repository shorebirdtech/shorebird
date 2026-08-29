import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/rollout_speed_sample.dart';

/// {@template get_rollout_speed_response}
/// The response body for GET /apps/{appId}/metrics/rollout-speed. One
/// flat sample per store release and per patch created within the
/// lookback window; comparisons and aggregates are composed by
/// consumers.
/// {@endtemplate}
@immutable
class GetRolloutSpeedResponse {
  /// {@macro get_rollout_speed_response}
  const GetRolloutSpeedResponse({
    required this.asOf,
    required this.lookbackDays,
    required this.rungs,
    required this.samples,
  });

  /// Converts a `Map<String, dynamic>` to a [GetRolloutSpeedResponse].
  factory GetRolloutSpeedResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetRolloutSpeedResponse',
      json,
      () => GetRolloutSpeedResponse(
        asOf: DateTime.parse(json['as_of'] as String),
        lookbackDays: json['lookback_days'] as int,
        rungs: (json['rungs'] as List).cast<double>(),
        samples: (json['samples'] as List)
            .map<RolloutSpeedSample>(
              (e) => RolloutSpeedSample.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetRolloutSpeedResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetRolloutSpeedResponse.fromJson(json);
  }

  /// Server's UTC timestamp at the moment the response was
  /// constructed. Not a freshness indicator for the underlying
  /// data, which is refreshed by an hourly scheduled query and
  /// may lag by up to ~1 hour.
  final DateTime asOf;

  /// The length of the sampling window: only artifacts created
  /// within this many days are considered. Fixed server-side and
  /// echoed here.
  final int lookbackDays;

  /// The rung shares crossings are reported for, ascending. Fixed
  /// server-side and echoed here.
  final List<double> rungs;

  /// One entry per release or patch, flat and independently
  /// queryable. Order is not significant.
  final List<RolloutSpeedSample> samples;

  /// Converts a [GetRolloutSpeedResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'as_of': asOf.toIso8601String(),
      'lookback_days': lookbackDays,
      'rungs': rungs,
      'samples': samples.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    asOf,
    lookbackDays,
    listHash(rungs),
    listHash(samples),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetRolloutSpeedResponse &&
        asOf == other.asOf &&
        lookbackDays == other.lookbackDays &&
        listsEqual(rungs, other.rungs) &&
        listsEqual(samples, other.samples);
  }
}
