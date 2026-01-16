import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';

/// DELETE /api/v1/apps/[appId] - Delete app
Future<Response> onRequest(RequestContext context, String appId) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  // Verify app exists and user has access
  final app = database.selectOne('apps', where: {'id': appId});
  if (app == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'App not found'},
    );
  }

  // Verify user has access to the organization
  final membership = database.selectOne(
    'organization_members',
    where: {
      'user_id': user['id'],
      'organization_id': app['organization_id'],
    },
  );

  if (membership == null) {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'message': 'You do not have access to this app'},
    );
  }

  // Delete app and related data
  database
    ..delete('apps', where: {'id': appId})
    ..delete('channels', where: {'app_id': appId});

  // Get releases and delete patches
  final releases = database.select('releases', where: {'app_id': appId});
  for (final release in releases) {
    final patches =
        database.select('patches', where: {'release_id': release['id']});
    for (final patch in patches) {
      database.delete('patch_artifacts', where: {'patch_id': patch['id']});
    }
    database
      ..delete('patches', where: {'release_id': release['id']})
      ..delete('release_artifacts', where: {'release_id': release['id']})
      ..delete(
        'release_platform_statuses',
        where: {'release_id': release['id']},
      );
  }
  database.delete('releases', where: {'app_id': appId});

  return Response(statusCode: HttpStatus.noContent);
}
