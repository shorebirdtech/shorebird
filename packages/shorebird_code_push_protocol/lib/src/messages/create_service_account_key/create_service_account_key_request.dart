import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_service_account_key_request}
/// The request body for POST
/// /organizations/{organizationId}/service-accounts/{serviceAccountId}/keys.
/// A body that includes `scope` is refused: a service account's key
/// takes no scope of its own.
/// {@endtemplate}
@immutable
class CreateServiceAccountKeyRequest {
  /// {@macro create_service_account_key_request}
  const CreateServiceAccountKeyRequest({
    required this.name,
    this.expiresInDays = 365,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateServiceAccountKeyRequest].
  factory CreateServiceAccountKeyRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateServiceAccountKeyRequest',
      json,
      () => CreateServiceAccountKeyRequest(
        name: json['name'] as String,
        expiresInDays: json.containsKey('expires_in_days')
            ? json['expires_in_days'] as int?
            : 365,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateServiceAccountKeyRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateServiceAccountKeyRequest.fromJson(json);
  }

  /// The key's name. Surrounding whitespace is trimmed; what remains
  /// must be 1 to 64 characters.
  final String name;

  /// How many days the key lasts, from 1 to 365. Omitted means 365.
  /// An explicit `null` issues a key that never expires.
  final int? expiresInDays;

  /// Converts a [CreateServiceAccountKeyRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'expires_in_days': expiresInDays,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    name,
    expiresInDays,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateServiceAccountKeyRequest &&
        name == other.name &&
        expiresInDays == other.expiresInDays;
  }
}
