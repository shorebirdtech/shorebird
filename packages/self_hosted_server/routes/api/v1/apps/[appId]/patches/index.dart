import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// POST /api/v1/apps/[appId]/patches - Create patch
Future<Response> onRequest(RequestContext context, String appId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  // Verify app exists
  final app = database.selectOne('apps', where: {'id': appId});
  if (app == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'App not found'},
    );
  }

  final body = await context.request.json() as Map<String, dynamic>;
  final request = CreatePatchRequest.fromJson(body);

  // Verify release exists
  final release = database.selectOne(
    'releases',
    where: {'id': request.releaseId, 'app_id': appId},
  );

  if (release == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'Release not found'},
    );
  }

  // Get next patch number
  final patchNumber = database.getNextPatchNumber(request.releaseId);

  final patchId = database.insert('patches', {
    'release_id': request.releaseId,
    'number': patchNumber,
    'metadata': jsonEncode(request.metadata),
  });

  final patch = Patch(
    id: patchId,
    number: patchNumber,
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: patch.toJson(),
  );
}
