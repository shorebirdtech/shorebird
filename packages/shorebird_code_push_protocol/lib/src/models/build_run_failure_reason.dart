/// Why a build run failed.
enum BuildRunFailureReason {
  /// The patch linked less of the release than --min-link-percentage.
  linkPercentage._('link_percentage'),

  /// Assets changed since the release, and the run stopped or the user
  /// declined to continue.
  assetDiffs._('asset_diffs'),

  /// Native code changed since the release, and the run stopped or the user
  /// declined to continue.
  nativeDiffs._('native_diffs'),

  /// The patch's --dart-define or --target differ from the release's, and the
  /// run stopped or the user declined to continue.
  buildFlagDiffs._('build_flag_diffs'),

  /// The Flutter, Xcode or Gradle build failed.
  buildFailed._('build_failed'),

  /// The release can't be patched, such as its Flutter is too old or it has
  /// no build for the platform.
  releaseIncompatible._('release_incompatible'),

  /// The Shorebird API refused a request.
  serverRejected._('server_rejected'),

  /// Uploading an artifact failed.
  uploadFailed._('upload_failed'),

  /// The user declined a confirmation.
  canceled._('canceled'),

  /// A failure the CLI does not classify.
  other._('other');

  const BuildRunFailureReason._(this.value);

  /// Creates a BuildRunFailureReason from a json value.
  factory BuildRunFailureReason.fromJson(String json) {
    return BuildRunFailureReason.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown BuildRunFailureReason value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static BuildRunFailureReason? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return BuildRunFailureReason.fromJson(json);
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
