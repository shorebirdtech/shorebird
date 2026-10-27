import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template update_organization_request}
/// The request body for PATCH /organizations/{organizationId}.
/// {@endtemplate}
@immutable
class UpdateOrganizationRequest {
  /// {@macro update_organization_request}
  const UpdateOrganizationRequest({
    required this.name,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdateOrganizationRequest].
  factory UpdateOrganizationRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UpdateOrganizationRequest',
      json,
      () => UpdateOrganizationRequest(
        name: json['name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdateOrganizationRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UpdateOrganizationRequest.fromJson(json);
  }

  /// The new name of the organization. Must not be blank.
  final String name;

  /// Converts a [UpdateOrganizationRequest] to a `Map<String, dynamic>`.
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
    return other is UpdateOrganizationRequest && name == other.name;
  }
}
