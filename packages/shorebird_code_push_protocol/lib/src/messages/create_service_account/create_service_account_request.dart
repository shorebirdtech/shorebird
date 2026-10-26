import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/service_account_role.dart';

/// {@template create_service_account_request}
/// The request body for POST /organizations/{organizationId}/service-accounts.
/// {@endtemplate}
@immutable
class CreateServiceAccountRequest {
  /// {@macro create_service_account_request}
  const CreateServiceAccountRequest({
    required this.name,
    this.role,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateServiceAccountRequest].
  factory CreateServiceAccountRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateServiceAccountRequest',
      json,
      () => CreateServiceAccountRequest(
        name: json['name'] as String,
        role: ServiceAccountRole.maybeFromJson(json['role'] as String?),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateServiceAccountRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateServiceAccountRequest.fromJson(json);
  }

  /// The service account's name. Surrounding whitespace is trimmed;
  /// what remains must be 1 to 64 characters.
  final String name;

  /// A role a service account can hold in its organization: a subset of
  /// `Role`. Never `admin` or `owner`, so a leaked key cannot manage the
  /// organization's members or its other service accounts.
  final ServiceAccountRole? role;

  /// Converts a [CreateServiceAccountRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'role': ?role?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    name,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateServiceAccountRequest &&
        name == other.name &&
        role == other.role;
  }
}
