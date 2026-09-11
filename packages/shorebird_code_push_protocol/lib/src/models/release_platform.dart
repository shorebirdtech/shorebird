/// A platform to which a Shorebird release can be deployed.
enum ReleasePlatform {
  /// Android.
  android._('android'),

  /// iOS.
  ios._('ios'),

  /// Linux.
  linux._('linux'),

  /// macOS.
  macos._('macos'),

  /// Windows.
  windows._('windows');

  const ReleasePlatform._(this.value);

  /// Creates a ReleasePlatform from a json value.
  factory ReleasePlatform.fromJson(String json) {
    return ReleasePlatform.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown ReleasePlatform value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static ReleasePlatform? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return ReleasePlatform.fromJson(json);
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
