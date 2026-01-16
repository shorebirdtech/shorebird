import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/organizations - List organizations
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  // Get organizations the user belongs to
  final memberships = database.select(
    'organization_members',
    where: {'user_id': user['id']},
  );

  final organizations = <OrganizationMembership>[];
  for (final membership in memberships) {
    final org = database.selectOne(
      'organizations',
      where: {'id': membership['organization_id']},
    );
    if (org != null) {
      organizations.add(
        OrganizationMembership(
          organization: Organization(
            id: org['id'] as int,
            name: org['name'] as String,
            organizationType: OrganizationType.personal,
            createdAt: DateTime.parse(org['created_at'] as String),
            updatedAt: DateTime.parse(org['updated_at'] as String),
          ),
          role: _parseRole(membership['role'] as String),
        ),
      );
    }
  }

  return Response.json(
    body: GetOrganizationsResponse(organizations: organizations).toJson(),
  );
}

Role _parseRole(String role) {
  switch (role) {
    case 'owner':
      return Role.owner;
    case 'admin':
      return Role.admin;
    default:
      return Role.developer;
  }
}
