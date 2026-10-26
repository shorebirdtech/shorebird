import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template app_store_connect_credential}
/// The App Store Connect team API key an organization gave Shorebird,
/// without its private key.
/// {@endtemplate}
@immutable
class AppStoreConnectCredential {
  /// {@macro app_store_connect_credential}
  const AppStoreConnectCredential({
    required this.id,
    required this.organizationId,
    required this.issuerId,
    required this.keyId,
    required this.uploadedByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Converts a `Map<String, dynamic>` to an [AppStoreConnectCredential].
  factory AppStoreConnectCredential.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AppStoreConnectCredential',
      json,
      () => AppStoreConnectCredential(
        id: json['id'] as int,
        organizationId: json['organization_id'] as int,
        issuerId: json['issuer_id'] as String,
        keyId: json['key_id'] as String,
        uploadedByUserId: checkedKey(json, 'uploaded_by_user_id') as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AppStoreConnectCredential? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AppStoreConnectCredential.fromJson(json);
  }

  /// The credential's ID.
  final int id;

  /// The organization the key belongs to.
  final int organizationId;

  /// The App Store Connect issuer id, in lowercase.
  final String issuerId;

  /// The App Store Connect key id.
  final String keyId;

  /// The person who last uploaded the key, while they still exist.
  final int? uploadedByUserId;

  /// When the organization first gave Shorebird a key.
  final DateTime createdAt;

  /// When the key was last uploaded.
  final DateTime updatedAt;

  /// Converts an [AppStoreConnectCredential] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'issuer_id': issuerId,
      'key_id': keyId,
      'uploaded_by_user_id': uploadedByUserId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    organizationId,
    issuerId,
    keyId,
    uploadedByUserId,
    createdAt,
    updatedAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppStoreConnectCredential &&
        id == other.id &&
        organizationId == other.organizationId &&
        issuerId == other.issuerId &&
        keyId == other.keyId &&
        uploadedByUserId == other.uploadedByUserId &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }
}
