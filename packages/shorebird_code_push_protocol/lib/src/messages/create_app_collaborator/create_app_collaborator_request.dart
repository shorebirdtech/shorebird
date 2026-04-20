import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_app_collaborator_request}
/// The request body for POST /apps/{appId}/collaborators.
/// {@endtemplate}
@immutable
class CreateAppCollaboratorRequest {
  /// {@macro create_app_collaborator_request}
  const CreateAppCollaboratorRequest({
    required this.email,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateAppCollaboratorRequest].
  factory CreateAppCollaboratorRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateAppCollaboratorRequest',
      json,
      () => CreateAppCollaboratorRequest(
        email: json['email'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateAppCollaboratorRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateAppCollaboratorRequest.fromJson(json);
  }

  /// The email of the collaborator to add.
  final String email;

  /// Converts a [CreateAppCollaboratorRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'email': email,
    };
  }

  @override
  int get hashCode => email.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateAppCollaboratorRequest && email == other.email;
  }
}
