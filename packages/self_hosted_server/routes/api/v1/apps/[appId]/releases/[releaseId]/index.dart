import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
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

  final body = await context.request.json() as Map<String, dynamic>;
  final request = UpdateReleaseRequest.fromJson(body);

  // TODO: Implement release status update in database
  // Update the status and metadata for the release

  return Response(statusCode: HttpStatus.noContent);
}
