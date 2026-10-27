// Spec descriptions copy prose verbatim into dartdoc, where `[x]`
// inside a sentence (placeholder text, ALL_CAPS tokens, license
// templates) is parsed as a symbol reference even when no such
// symbol exists. Suppress file-locally so the lint stays live
// elsewhere; spec authors do not always escape brackets.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/service_account_role.dart';

/// {@template service_account}
/// A non-human account owned by an organization, for CI and other
/// automation. It authenticates only with API keys issued to it or
/// under OIDC trust rules, and is shown as `label` (`name[bot]`).
/// {@endtemplate}
@immutable
class ServiceAccount {
  /// {@macro service_account}
  const ServiceAccount({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.label,
    required this.role,
    required this.createdAt,
    required this.createdByUserId,
    required this.createdByEmail,
    required this.lastAuthAt,
  });

  /// Converts a `Map<String, dynamic>` to a [ServiceAccount].
  factory ServiceAccount.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ServiceAccount',
      json,
      () => ServiceAccount(
        id: json['id'] as int,
        organizationId: json['organization_id'] as int,
        name: json['name'] as String,
        label: json['label'] as String,
        role: ServiceAccountRole.fromJson(json['role'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        createdByUserId: checkedKey(json, 'created_by_user_id') as int?,
        createdByEmail: checkedKey(json, 'created_by_email') as String?,
        lastAuthAt: maybeParseDateTime(
          checkedKey(json, 'last_auth_at') as String?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ServiceAccount? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ServiceAccount.fromJson(json);
  }

  /// The service account's ID, which is also its user ID.
  final int id;

  /// The organization that owns the service account.
  final int organizationId;

  /// The service account's name.
  final String name;

  /// The name the service account is shown by, `name[bot]`.
  final String label;

  /// The service account's role in its organization.
  final ServiceAccountRole role;

  /// When the service account was created.
  final DateTime createdAt;

  /// The user who created the service account, or null once that user
  /// has been deleted.
  final int? createdByUserId;

  /// The email of the user who created the service account, or null
  /// once that user has been deleted.
  final String? createdByEmail;

  /// When the service account last authenticated, or null if it never
  /// has. Refreshed at most once a day.
  final DateTime? lastAuthAt;

  /// Converts a [ServiceAccount] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'name': name,
      'label': label,
      'role': role.toJson(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'created_by_user_id': createdByUserId,
      'created_by_email': createdByEmail,
      'last_auth_at': lastAuthAt?.toUtc().toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    organizationId,
    name,
    label,
    role,
    createdAt,
    createdByUserId,
    createdByEmail,
    lastAuthAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServiceAccount &&
        id == other.id &&
        organizationId == other.organizationId &&
        name == other.name &&
        label == other.label &&
        role == other.role &&
        createdAt == other.createdAt &&
        createdByUserId == other.createdByUserId &&
        createdByEmail == other.createdByEmail &&
        lastAuthAt == other.lastAuthAt;
  }
}
