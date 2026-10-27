/// The verdict of a release artifact's size analysis.
enum SizeAnalysisStatus {
  /// The analysis ran, and the size fields hold its result.
  succeeded._('succeeded'),

  /// The analysis could not run because no analyzer has been published for
  /// the release's snapshot format. It may run once one is.
  analyzeSnapshotUnpublished._('analyze_snapshot_unpublished'),

  /// The analysis failed in a way retrying will not fix.
  failedPermanent._('failed_permanent');

  const SizeAnalysisStatus._(this.value);

  /// Creates a SizeAnalysisStatus from a json value.
  factory SizeAnalysisStatus.fromJson(String json) {
    return SizeAnalysisStatus.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown SizeAnalysisStatus value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static SizeAnalysisStatus? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return SizeAnalysisStatus.fromJson(json);
  }

  /// The value of the enum.  This is the exact value
  /// from the OpenAPI spec and will be used for network transport.
  final String value;

  /// Converts the enum to its json value.
  String toJson() => value;

  /// Returns the string form of the enum.
  @override
  String toString() => value;
}
