import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_user_request}
/// The request body for POST /users. The user's email is taken
/// from the auth token; only the display name is provided here.
/// {@endtemplate}
@immutable
class CreateUserRequest {
  /// {@macro create_user_request}
  const CreateUserRequest({
    required this.name,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateUserRequest].
  factory CreateUserRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateUserRequest',
      json,
      () => CreateUserRequest(
        name: json['name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateUserRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateUserRequest.fromJson(json);
  }

  /// The new user's display name.
  final String name;

  /// Converts a [CreateUserRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }

  @override
  int get hashCode => name.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateUserRequest && name == other.name;
  }
}
