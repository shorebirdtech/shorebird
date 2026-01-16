import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// PATCH /api/v1/apps/[appId]/releases/[releaseId] - Update release status
Future<Response> onRequest(
  RequestContext context,
  String appId,
  String releaseId,
) async {
  if (context.request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  final releaseIdInt = int.tryParse(releaseId);
  if (releaseIdInt == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'Invalid release ID'},
    );
  }

  // Verify release exists
  final release = database.selectOne(
    'releases',
    where: {'id': releaseIdInt, 'app_id': appId},
  );

  if (release == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'Release not found'},
    );
  }

  final body = await context.request.json() as Map<String, dynamic>;
  final request = UpdateReleaseRequest.fromJson(body);

  // Update or create platform status
  final existingStatus = database.selectOne(
    'release_platform_statuses',
    where: {'release_id': releaseIdInt, 'platform': request.platform.name},
  );

  if (existingStatus != null) {
    database.update(
      'release_platform_statuses',
      data: {'status': request.status.name},
      where: {'id': existingStatus['id']},
    );
  } else {
    database.insert('release_platform_statuses', {
      'release_id': releaseIdInt,
      'platform': request.platform.name,
      'status': request.status.name,
    });
  }

  return Response(statusCode: HttpStatus.noContent);
}
