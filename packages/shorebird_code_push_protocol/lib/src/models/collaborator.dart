import 'package:json_annotation/json_annotation.dart';

part 'collaborator.g.dart';

/// {@template collaborator_role}
/// The role a user has for an app.
/// {@endtemplate}
enum CollaboratorRole {
  /// A user with this role can perform all available actions on apps, releases,
  /// patches, channels, and collaborators.
  admin('admin'),

  /// A user with this role can manage releases and patches, but cannot manage
  /// collaborators or the application itself.
  developer('developer');

  /// {@macro collaborator_role}
  const CollaboratorRole(this.name);

  /// The name of the role.
  final String name;
}

/// {@template collaborator}
/// A user who has permission to collaborate on an app.
/// {@endtemplate}
@JsonSerializable()
class Collaborator {
  /// {@macro collaborator}
  const Collaborator({
    required this.userId,
    required this.email,
    required this.role,
  });

  /// Converts a Map<String, dynamic> to an [Collaborator]
  factory Collaborator.fromJson(Map<String, dynamic> json) =>
      _$CollaboratorFromJson(json);

  /// Converts a [Collaborator] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CollaboratorToJson(this);

  /// The unique identifier for the user.
  final int userId;

  /// The email address of the user.
  final String email;

  /// The role the user has for the app. Roles are used to determine permissions
  /// and what actions a user can perform on an app.
  final CollaboratorRole role;
}
