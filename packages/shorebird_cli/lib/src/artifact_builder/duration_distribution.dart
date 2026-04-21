/// Summary statistics over a list of Durations — count, total, p50,
/// p90, and max. Produced by [DurationDistribution.fromDurations];
/// serialized as a nested object in the build-trace summary JSON
/// under keys `{count, sumMs, p50Ms, p90Ms, maxMs}`.
class DurationDistribution {
  /// Creates a [DurationDistribution] directly from precomputed fields.
  /// Most callers should use [DurationDistribution.fromDurations] or
  /// [DurationDistribution.empty].
  DurationDistribution({
    required this.count,
    required this.sum,
    required this.p50,
    required this.p90,
    required this.max,
  });

  /// Empty distribution: count 0, all durations [Duration.zero].
  factory DurationDistribution.empty() => DurationDistribution(
    count: 0,
    sum: Duration.zero,
    p50: Duration.zero,
    p90: Duration.zero,
    max: Duration.zero,
  );

  /// Computes a distribution from a list of Durations. Empty input
  /// returns [DurationDistribution.empty]. Durations implement
  /// Comparable, so we sort in place (well, on a copy) to pick
  /// percentiles.
  factory DurationDistribution.fromDurations(List<Duration> values) {
    if (values.isEmpty) return DurationDistribution.empty();
    final sorted = [...values]..sort();
    Duration at(double q) {
      final idx = (sorted.length * q).floor().clamp(0, sorted.length - 1);
      return sorted[idx];
    }

    return DurationDistribution(
      count: sorted.length,
      sum: sorted.fold(Duration.zero, (a, b) => a + b),
      p50: at(0.5),
      p90: at(0.9),
      max: sorted.last,
    );
  }

  /// Number of samples in the distribution.
  final int count;

  /// Sum of all samples.
  final Duration sum;

  /// Median (50th percentile) of the samples.
  final Duration p50;

  /// 90th percentile of the samples.
  final Duration p90;

  /// Maximum sample.
  final Duration max;

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'count': count,
    'sumMs': sum.inMilliseconds,
    'p50Ms': p50.inMilliseconds,
    'p90Ms': p90.inMilliseconds,
    'maxMs': max.inMilliseconds,
  };
}
