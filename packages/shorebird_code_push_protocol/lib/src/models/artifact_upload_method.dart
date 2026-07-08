/// How a client should upload an artifact's bytes to storage.
///
/// Returned by the create-artifact endpoints so the client knows how to use the
/// `url` it was handed. Absent (null) on responses from older servers, which
/// always implied [multipart].
enum ArtifactUploadMethod {
  /// Legacy single `multipart/form-data` POST of the file to a signed URL.
  multipart._('multipart'),

  /// Resumable upload: PUT the bytes (chunked, with `Content-Range`) to a
  /// server-initiated GCS resumable session URI given in `url`. The session is
  /// size-bound at initiation, so GCS rejects an oversized upload.
  resumable._('resumable');

  const ArtifactUploadMethod._(this.value);

  /// Creates an [ArtifactUploadMethod] from a json value.
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

  /// The wire value of the enum, used for network transport.
  final String value;

  /// Converts the enum to its json value.
  String toJson() => value;

  /// Returns the string form of the enum.
  @override
  String toString() => value;
}
