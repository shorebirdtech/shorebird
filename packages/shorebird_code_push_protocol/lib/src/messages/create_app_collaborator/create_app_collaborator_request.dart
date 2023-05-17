import 'package:json_annotation/json_annotation.dart';

part 'create_app_collaborator_request.g.dart';

/// {@template create_app_collaborator_request}
/// The request body for POST /api/v1/apps/<id>/collaborators
/// {@endtemplate}
@JsonSerializable()
class CreateAppCollaboratorRequest {
  /// {@macro create_app_collaborator_request}
  const CreateAppCollaboratorRequest({required this.email});

  /// Converts a Map<String, dynamic> to a [CreateAppCollaboratorRequest]
  factory CreateAppCollaboratorRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateAppCollaboratorRequestFromJson(json);

  /// Converts a [CreateAppCollaboratorRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreateAppCollaboratorRequestToJson(this);

  /// The email of the collaborator to add.
  final String email;
}
