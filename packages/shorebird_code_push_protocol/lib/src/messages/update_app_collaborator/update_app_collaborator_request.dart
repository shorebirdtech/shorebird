import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/app_collaborator_role.dart';

/// {@template update_app_collaborator_request}
/// The request body for PATCH /apps/{appId}/collaborators/{collaboratorId}.
/// {@endtemplate}
@immutable
class UpdateAppCollaboratorRequest {
  /// {@macro update_app_collaborator_request}
  const UpdateAppCollaboratorRequest({
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdateAppCollaboratorRequest].
  factory UpdateAppCollaboratorRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UpdateAppCollaboratorRequest',
      json,
      () => UpdateAppCollaboratorRequest(
        role: AppCollaboratorRole.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdateAppCollaboratorRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return UpdateAppCollaboratorRequest.fromJson(json);
  }

  /// A role a user can have on a specific app.
  final AppCollaboratorRole role;

  /// Converts a [UpdateAppCollaboratorRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => role.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateAppCollaboratorRequest && role == other.role;
  }
}
