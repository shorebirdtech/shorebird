/// What GET /apps/{appId}/releases/{releaseId}/size-analysis returns
/// in place of the summary.
enum ReleaseSizeAnalysisInclude {
  /// The platform's full size tree.
  tree._('tree');

  const ReleaseSizeAnalysisInclude._(this.value);

  /// Creates a ReleaseSizeAnalysisInclude from a json value.
  factory ReleaseSizeAnalysisInclude.fromJson(String json) {
    return ReleaseSizeAnalysisInclude.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown ReleaseSizeAnalysisInclude value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ReleaseSizeAnalysisInclude? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ReleaseSizeAnalysisInclude.fromJson(json);
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
