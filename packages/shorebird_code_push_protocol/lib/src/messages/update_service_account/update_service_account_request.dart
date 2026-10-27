import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/service_account_role.dart';

/// {@template update_service_account_request}
/// The request body for PATCH
/// /organizations/{organizationId}/service-accounts/{serviceAccountId}.
/// {@endtemplate}
@immutable
class UpdateServiceAccountRequest {
  /// {@macro update_service_account_request}
  const UpdateServiceAccountRequest({
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdateServiceAccountRequest].
  factory UpdateServiceAccountRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UpdateServiceAccountRequest',
      json,
      () => UpdateServiceAccountRequest(
        role: ServiceAccountRole.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdateServiceAccountRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return UpdateServiceAccountRequest.fromJson(json);
  }

  /// A role a service account can hold in its organization: a subset of
  /// `Role`. Never `admin` or `owner`, so a leaked key cannot manage the
  /// organization's members or its other service accounts.
  final ServiceAccountRole role;

  /// Converts a [UpdateServiceAccountRequest] to a `Map<String, dynamic>`.
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
    return other is UpdateServiceAccountRequest && role == other.role;
  }
}
