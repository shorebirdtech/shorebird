import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:self_hosted_server/self_hosted_server.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// POST /api/v1/users - Create user
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  // This endpoint requires authentication to create users
  final currentUser = await authenticateRequest(context);
  if (currentUser == null) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  final body = await context.request.json() as Map<String, dynamic>;
  final request = CreateUserRequest.fromJson(body);

  // For the Shorebird CLI, this is typically called after OAuth
  // In self-hosted, we create the user if they don't exist
  final existingUser = database.selectOne(
    'users',
    where: {'id': currentUser['id']},
  );
  if (existingUser == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'message': 'User not found'},
    );
  }

  // Update display name if provided
  if (request.name != existingUser['display_name']) {
    database.update(
      'users',
      data: {'display_name': request.name},
      where: {'id': currentUser['id']},
    );
  }

  final updatedUser = database.selectOne(
    'users',
    where: {'id': currentUser['id']},
  );

  final user = PrivateUser(
    id: updatedUser!['id'] as int,
    email: updatedUser['email'] as String,
    jwtIssuer: 'self-hosted',
    displayName: updatedUser['display_name'] as String?,
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: user.toJson(),
  );
}
