import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template service_account_key}
/// An API key issued to a service account. Never carries the key's
/// secret, which is returned only when the key is issued.
/// {@endtemplate}
@immutable
class ServiceAccountKey {
  /// {@macro service_account_key}
  const ServiceAccountKey({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    required this.scopes,
  });

  /// Converts a `Map<String, dynamic>` to a [ServiceAccountKey].
  factory ServiceAccountKey.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ServiceAccountKey',
      json,
      () => ServiceAccountKey(
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
  static ServiceAccountKey? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ServiceAccountKey.fromJson(json);
  }

  /// The key's ID.
  final int id;

  /// The key's name.
  final String name;

  /// When the key was issued.
  final DateTime createdAt;

  /// When the key was last used, or null if it never has been.
  final DateTime? lastUsedAt;

  /// When the key expires, or null if it never does.
  final DateTime? expiresAt;

  /// The key's scopes by wire name. A service account's key is issued
  /// with `api` and does what the account's role allows.
  final List<String> scopes;

  /// Converts a [ServiceAccountKey] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
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
    return other is ServiceAccountKey &&
        id == other.id &&
        name == other.name &&
        createdAt == other.createdAt &&
        lastUsedAt == other.lastUsedAt &&
        expiresAt == other.expiresAt &&
        listsEqual(scopes, other.scopes);
  }
}
