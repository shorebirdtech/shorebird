import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// GET /api/v1/users/me - Get current user
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  // TODO: Implement authentication and user lookup from JWT token
  // For now, return a mock user
  final user = PrivateUser(
    id: 1,
    email: 'user@example.com',
    displayName: 'Demo User',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  return Response.json(body: user.toJson());
}
