import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/users/me - Get current user
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = await authenticateRequest(context);
  if (user == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  final privateUser = PrivateUser(
    id: user['id'] as int,
    email: user['email'] as String,
    displayName: user['display_name'] as String,
    createdAt: DateTime.parse(user['created_at'] as String),
    updatedAt: DateTime.parse(user['updated_at'] as String),
  );

  return Response.json(body: privateUser.toJson());
}
