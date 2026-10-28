import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Enterprise models shared by the enterprise-scope tests, read from the
/// JSON the server sends.
abstract final class EnterpriseFixtures {
  static final acme = EnterpriseMembership.fromJson(const {
    'id': 7,
    'name': 'Acme',
    'role': 'admin',
  });

  static final beacon = EnterpriseMembership.fromJson(const {
    'id': 8,
    'name': 'Beacon',
    'role': 'member',
  });

  static final acmeEnterprise = Enterprise.fromJson(const {
    'id': 7,
    'name': 'Acme',
    'domains': ['acme.com', 'acme.dev'],
  });

  static final mobile = EnterpriseTeam.fromJson(const {
    'id': 42,
    'name': 'Mobile',
    'member_count': 12,
    'app_count': 1,
    'default_role': null,
    'apps': [
      {'id': 'app-1', 'display_name': 'Acme App'},
    ],
  });

  static final app = EnterpriseApp.fromJson(const {
    'organization_id': 42,
    'organization_name': 'Mobile',
    'app_id': 'app-1',
    'app_display_name': 'Acme App',
  });

  static EnterpriseMember member({
    int userId = 9,
    String? email = 'bob@acme.com',
    String role = 'member',
    String? removedAt,
  }) => EnterpriseMember.fromJson({
    'user_id': userId,
    'email': email,
    'display_name': 'Bob',
    'kind': 'user',
    'role': role,
    'teams': const [
      {'team_id': 42, 'role': 'developer'},
      {'team_id': 43, 'role': 'viewer'},
    ],
    'app_grants': const <Object>[],
    'sign_in_method': null,
    'signed_in_at': null,
    'last_active_at': null,
    'removed_at': removedAt,
    'removed_by_email': null,
  });

  static final guest = EnterpriseGuest.fromJson(const {
    'user_id': 10,
    'email': 'eve@contractor.com',
    'display_name': null,
    'kind': 'user',
    'outside_guest_policy': true,
    'teams': [
      {'team_id': 42, 'role': 'viewer'},
    ],
    'app_grants': <Object>[],
    'sign_in_method': null,
    'signed_in_at': null,
    'last_active_at': null,
  });

  static final removal = RemoveEnterpriseMember200Response.fromJson(const {
    'organizations': [
      {
        'organization_id': 42,
        'organization_name': 'Mobile',
        'role': 'developer',
      },
      {'organization_id': 43, 'organization_name': 'Web', 'role': 'viewer'},
    ],
    'app_grants': [
      {'app_id': 'app-2', 'organization_id': 44, 'role': 'developer'},
    ],
    'invitations_revoked': 0,
    'sessions_revoked': 2,
    'api_keys_revoked': 1,
  });
}
