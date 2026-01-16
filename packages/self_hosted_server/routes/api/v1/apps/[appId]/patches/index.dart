import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// POST /api/v1/apps/[appId]/patches - Create patch
Future<Response> onRequest(RequestContext context, String appId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final body = await context.request.json() as Map<String, dynamic>;
  final request = CreatePatchRequest.fromJson(body);

  // TODO: Implement patch creation in database
  final patch = Patch(
    id: DateTime.now().millisecondsSinceEpoch,
    number: 1, // This should be incremented based on existing patches
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: patch.toJson(),
  );
}
