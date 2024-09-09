/// {@template app_collaborator_role}
/// The role a user has for a specific app. Roles are associated with different
/// permission levels.
/// {@endtemplate}
enum AppCollaboratorRole {
  /// A user with this role can perform all available actions on apps, releases,
  /// patches, channels, and collaborators.
  admin('admin'),

  /// A user with this role can manage releases and patches, but cannot manage
  /// collaborators or the application itself.
  developer('developer');

  /// {@macro app_collaborator_role}
  const AppCollaboratorRole(this.name);

  /// The name of the role.
  final String name;
}
