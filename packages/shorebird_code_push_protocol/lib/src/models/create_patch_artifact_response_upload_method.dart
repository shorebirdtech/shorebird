/// How to upload the artifact bytes to `url`: a single multipart POST
/// (legacy), or a PUT (chunked, resumable) to a resumable session URI.
/// Absent on responses from older servers, which implied multipart.
enum CreatePatchArtifactResponseUploadMethod {
  multipart._('multipart'),
  resumable._('resumable');

  const CreatePatchArtifactResponseUploadMethod._(this.value);

  /// Creates a CreatePatchArtifactResponseUploadMethod from a json value.
  factory CreatePatchArtifactResponseUploadMethod.fromJson(String json) {
    return CreatePatchArtifactResponseUploadMethod.values.firstWhere(
      (value) => value.value == json,
      orElse: () => throw FormatException(
        'Unknown CreatePatchArtifactResponseUploadMethod value: $json',
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static CreatePatchArtifactResponseUploadMethod? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return CreatePatchArtifactResponseUploadMethod.fromJson(json);
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
