import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';

/// POST /api/v1/auth/register - Register new user
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final body = await context.request.json() as Map<String, dynamic>;
  final email = body['email'] as String?;
  final password = body['password'] as String?;
  final displayName = body['display_name'] as String?;

  if (email == null || password == null || displayName == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'email, password, and display_name are required'},
    );
  }

  final userId = authService.register(
    email: email,
    password: password,
    displayName: displayName,
  );

  if (userId == null) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {'error': 'User with this email already exists'},
    );
  }

  final token = authService.generateToken(userId, email);

  return Response.json(
    statusCode: HttpStatus.created,
    body: {
      'user_id': userId,
      'token': token,
    },
  );
}
