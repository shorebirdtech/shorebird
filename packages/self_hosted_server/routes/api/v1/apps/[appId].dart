import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// DELETE /api/v1/apps/[appId] - Delete app
Future<Response> onRequest(RequestContext context, String appId) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  // TODO: Implement app deletion from database
  // Also delete associated releases, patches, and artifacts from storage

  return Response(statusCode: HttpStatus.noContent);
}
