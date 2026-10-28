/// How a client should upload an artifact's bytes to storage.
enum ArtifactUploadMethod {
  multipart._('multipart'),
  resumable._('resumable');

  const ArtifactUploadMethod._(this.value);

  /// Creates a ArtifactUploadMethod from a json value.
  factory ArtifactUploadMethod.fromJson(String json) {
    return ArtifactUploadMethod.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown ArtifactUploadMethod value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ArtifactUploadMethod? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ArtifactUploadMethod.fromJson(json);
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
