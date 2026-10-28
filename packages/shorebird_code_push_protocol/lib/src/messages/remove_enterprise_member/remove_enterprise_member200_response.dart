import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_removed_access_app_grants_inner.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_removed_access_organizations_inner.dart';

@immutable
class RemoveEnterpriseMember200Response {
  const RemoveEnterpriseMember200Response({
    required this.organizations,
    required this.appGrants,
    required this.invitationsRevoked,
    required this.sessionsRevoked,
    required this.apiKeysRevoked,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [RemoveEnterpriseMember200Response].
  factory RemoveEnterpriseMember200Response.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'RemoveEnterpriseMember200Response',
      json,
      () => RemoveEnterpriseMember200Response(
        organizations: (json['organizations'] as List)
            .map<EnterpriseRemovedAccessOrganizationsInner>(
              (e) => EnterpriseRemovedAccessOrganizationsInner.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
        appGrants: (json['app_grants'] as List)
            .map<EnterpriseRemovedAccessAppGrantsInner>(
              (e) => EnterpriseRemovedAccessAppGrantsInner.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
        invitationsRevoked: json['invitations_revoked'] as int,
        sessionsRevoked: json['sessions_revoked'] as int,
        apiKeysRevoked: json['api_keys_revoked'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static RemoveEnterpriseMember200Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return RemoveEnterpriseMember200Response.fromJson(json);
  }

  final List<EnterpriseRemovedAccessOrganizationsInner> organizations;
  final List<EnterpriseRemovedAccessAppGrantsInner> appGrants;
  final int invitationsRevoked;
  final int sessionsRevoked;
  final int apiKeysRevoked;

  /// Converts a [RemoveEnterpriseMember200Response]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'organizations': organizations.map((e) => e.toJson()).toList(),
      'app_grants': appGrants.map((e) => e.toJson()).toList(),
      'invitations_revoked': invitationsRevoked,
      'sessions_revoked': sessionsRevoked,
      'api_keys_revoked': apiKeysRevoked,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(organizations),
    listHash(appGrants),
    invitationsRevoked,
    sessionsRevoked,
    apiKeysRevoked,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RemoveEnterpriseMember200Response &&
        listsEqual(organizations, other.organizations) &&
        listsEqual(appGrants, other.appGrants) &&
        invitationsRevoked == other.invitationsRevoked &&
        sessionsRevoked == other.sessionsRevoked &&
        apiKeysRevoked == other.apiKeysRevoked;
  }
}
