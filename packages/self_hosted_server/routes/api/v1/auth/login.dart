import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';

/// POST /api/v1/auth/login - Login user
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final body = await context.request.json() as Map<String, dynamic>;
  final email = body['email'] as String?;
  final password = body['password'] as String?;

  if (email == null || password == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'email and password are required'},
    );
  }

  final token = authService.login(email: email, password: password);

  if (token == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'Invalid email or password'},
    );
  }

  final user = authService.getUserByEmail(email);

  return Response.json(
    body: {
      'token': token,
      'user': {
        'id': user!['id'],
        'email': user['email'],
        'display_name': user['display_name'],
      },
    },
  );
}
