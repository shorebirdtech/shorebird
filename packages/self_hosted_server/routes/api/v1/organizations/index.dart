import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/organizations - List organizations
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  // TODO: Implement organization listing from database
  final organizations = <OrganizationMembership>[
    OrganizationMembership(
      organization: Organization(
        id: 1,
        name: 'Default Organization',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      role: OrganizationRole.owner,
    ),
  ];

  return Response.json(
    body: GetOrganizationsResponse(organizations: organizations).toJson(),
  );
}
