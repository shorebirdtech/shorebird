import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'create_user_request.g.dart';

/// {@template create_user_request}
/// The request body for POST /api/v1/users, which creates a new User.
///
/// Email is retrieved from the user's auth token.
/// {@endtemplate}
@JsonSerializable()
class CreateUserRequest {
  /// {@macro create_user_request}
  const CreateUserRequest({
    required this.name,
  });

  /// Converts a JSON object to a [CreateUserRequest].
  factory CreateUserRequest.fromJson(Json json) =>
      _$CreateUserRequestFromJson(json);

  /// Converts a [CreateUserRequest] to a JSON object.
  Json toJson() => _$CreateUserRequestToJson(this);

  /// The new user's display name.
  final String name;
}
