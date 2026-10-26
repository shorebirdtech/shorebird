import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template app_collaborator}
/// A user holding a per-app role on an app.
/// {@endtemplate}
@immutable
class AppCollaborator {
  /// {@macro app_collaborator}
  const AppCollaborator({
    required this.userId,
    required this.email,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an [AppCollaborator].
  factory AppCollaborator.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AppCollaborator',
      json,
      () => AppCollaborator(
        userId: json['user_id'] as int,
        email: json['email'] as String,
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AppCollaborator? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AppCollaborator.fromJson(json);
  }

  /// The user's ID. This is the `collaboratorId` that
  /// PATCH and DELETE /apps/{appId}/collaborators/{collaboratorId}
  /// take.
  final int userId;

  /// The user's email address.
  final String email;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [AppCollaborator] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'email': email,
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    userId,
    email,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppCollaborator &&
        userId == other.userId &&
        email == other.email &&
        role == other.role;
  }
}
