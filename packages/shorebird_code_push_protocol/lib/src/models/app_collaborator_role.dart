/// A role a user can have on a specific app.
enum AppCollaboratorRole {
  /// A user with this role can perform all available actions on apps,
  /// releases, patches, channels, and collaborators.
  admin._('admin'),

  /// A user with this role can manage releases and patches, but cannot manage
  /// collaborators or the application itself.
  developer._('developer');

  const AppCollaboratorRole._(this.value);

  /// Creates a AppCollaboratorRole from a json value.
  factory AppCollaboratorRole.fromJson(String json) {
    return AppCollaboratorRole.values.firstWhere(
      (value) => value.value == json,
      orElse: () =>
          throw FormatException('Unknown AppCollaboratorRole value: $json'),
    );
  }

  /// Convenience to create a nullable type from a nullable json value.
  /// Useful when parsing optional fields.
  static AppCollaboratorRole? maybeFromJson(String? json) {
    if (json == null) {
      return null;
    }
    return AppCollaboratorRole.fromJson(json);
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
