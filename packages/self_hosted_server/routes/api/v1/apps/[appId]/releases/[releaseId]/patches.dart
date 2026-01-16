import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/apps/[appId]/releases/[releaseId]/patches - List patches
Future<Response> onRequest(
  RequestContext context,
  String appId,
  String releaseId,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  // TODO: Implement patch listing from database
  final patches = <ReleasePatch>[];

  return Response.json(
    body: GetReleasePatchesResponse(patches: patches).toJson(),
  );
}
