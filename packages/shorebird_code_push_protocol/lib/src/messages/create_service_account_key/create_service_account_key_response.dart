import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_service_account_key_response}
/// The response body for POST
/// /organizations/{organizationId}/service-accounts/{serviceAccountId}/keys:
/// the new key, plus its secret.
/// {@endtemplate}
@immutable
class CreateServiceAccountKeyResponse {
  /// {@macro create_service_account_key_response}
  const CreateServiceAccountKeyResponse({
    required this.apiKey,
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    required this.scopes,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateServiceAccountKeyResponse].
  factory CreateServiceAccountKeyResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateServiceAccountKeyResponse',
      json,
      () => CreateServiceAccountKeyResponse(
        apiKey: json['api_key'] as String,
        id: json['id'] as int,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        lastUsedAt: maybeParseDateTime(
          checkedKey(json, 'last_used_at') as String?,
        ),
        expiresAt: maybeParseDateTime(
          checkedKey(json, 'expires_at') as String?,
        ),
        scopes: (json['scopes'] as List).cast<String>(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateServiceAccountKeyResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateServiceAccountKeyResponse.fromJson(json);
  }

  /// The key's secret, an `sb_api_*` token to send as a bearer token.
  /// Returned only here: store it now, since no later call returns it.
  final String apiKey;

  /// The key's ID.
  final int id;

  /// The key's name.
  final String name;

  /// When the key was issued.
  final DateTime createdAt;

  /// When the key was last used; null for a new key.
  final DateTime? lastUsedAt;

  /// When the key expires, or null if it never does.
  final DateTime? expiresAt;

  /// The key's scopes by wire name, `["api"]`.
  final List<String> scopes;

  /// Converts a [CreateServiceAccountKeyResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'api_key': apiKey,
      'id': id,
      'name': name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'last_used_at': lastUsedAt?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'scopes': scopes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    apiKey,
    id,
    name,
    createdAt,
    lastUsedAt,
    expiresAt,
    listHash(scopes),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateServiceAccountKeyResponse &&
        apiKey == other.apiKey &&
        id == other.id &&
        name == other.name &&
        createdAt == other.createdAt &&
        lastUsedAt == other.lastUsedAt &&
        expiresAt == other.expiresAt &&
        listsEqual(scopes, other.scopes);
  }
}
