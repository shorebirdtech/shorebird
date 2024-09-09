import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'update_app_collaborator_request.g.dart';

/// {@template update_app_collaborator_request}
/// The request body for
/// PATCH /api/v1/apps/<appId>/collaborators/<collaboratorId>
/// {@endtemplate}
@JsonSerializable()
class UpdateAppCollaboratorRequest {
  /// {@macro update_app_collaborator_request}
  const UpdateAppCollaboratorRequest({
    required this.role,
  });

  /// Converts a Map<String, dynamic> to a [UpdateAppCollaboratorRequest].
  factory UpdateAppCollaboratorRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateAppCollaboratorRequestFromJson(json);

  /// Converts a [UpdateAppCollaboratorRequest] to a Map<String, dynamic>.
  Map<String, dynamic> toJson() => _$UpdateAppCollaboratorRequestToJson(this);

  /// The new role for the collaborator.
  final AppCollaboratorRole role;
}
