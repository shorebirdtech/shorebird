import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';

/// POST /api/v1/apps/[appId]/patches/promote - Promote patch to channel
Future<Response> onRequest(RequestContext context, String appId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  final body = await context.request.json() as Map<String, dynamic>;
  final patchId = body['patch_id'] as int?;
  final channelId = body['channel_id'] as int?;

  if (patchId == null || channelId == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': 'patch_id and channel_id are required'},
    );
  }

  // Verify patch exists
  final patch = database.selectOne('patches', where: {'id': patchId});
  if (patch == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'Patch not found'},
    );
  }

  // Verify channel exists
  final channel = database.selectOne('channels', where: {'id': channelId});
  if (channel == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'Channel not found'},
    );
  }

  // Check if already promoted
  final existing = database.selectOne(
    'channel_patches',
    where: {'patch_id': patchId, 'channel_id': channelId},
  );

  if (existing == null) {
    // Promote patch to channel
    database.insert('channel_patches', {
      'patch_id': patchId,
      'channel_id': channelId,
    });
  }

  return Response(statusCode: HttpStatus.noContent);
}
