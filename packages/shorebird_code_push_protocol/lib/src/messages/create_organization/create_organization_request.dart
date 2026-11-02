import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_organization_request}
/// The request body for POST /organizations.
/// {@endtemplate}
@immutable
class CreateOrganizationRequest {
  /// {@macro create_organization_request}
  const CreateOrganizationRequest({
    required this.name,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateOrganizationRequest].
  factory CreateOrganizationRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateOrganizationRequest',
      json,
      () => CreateOrganizationRequest(
        name: json['name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateOrganizationRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateOrganizationRequest.fromJson(json);
  }

  /// The name of the organization. Must not be blank.
  final String name;

  /// Converts a [CreateOrganizationRequest] to a `Map<String, dynamic>`.
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
    return other is CreateOrganizationRequest && name == other.name;
  }
}
