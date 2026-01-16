import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// POST /api/v1/apps/[appId]/patches/promote - Promote patch to channel
Future<Response> onRequest(RequestContext context, String appId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final body = await context.request.json() as Map<String, dynamic>;
  final patchId = body['patch_id'] as int;
  final channelId = body['channel_id'] as int;

  // TODO: Implement patch promotion in database
  // Link the patch to the specified channel

  return Response(statusCode: HttpStatus.noContent);
}
