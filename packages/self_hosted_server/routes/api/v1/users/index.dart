import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// POST /api/v1/users - Create user
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => _createUser(context),
    _ => Future.value(
        Response(statusCode: HttpStatus.methodNotAllowed),
      ),
  };
}

Future<Response> _createUser(RequestContext context) async {
  final body = await context.request.json() as Map<String, dynamic>;
  final request = CreateUserRequest.fromJson(body);

  // TODO: Implement user creation in database
  final user = PrivateUser(
    id: 1,
    email: 'newuser@example.com',
    displayName: request.name,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  return Response.json(
    statusCode: HttpStatus.created,
    body: user.toJson(),
  );
}
