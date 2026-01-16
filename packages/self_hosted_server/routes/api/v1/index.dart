import 'package:dart_frog/dart_frog.dart';

/// API v1 root handler.
Response onRequest(RequestContext context) {
  return Response.json(
    body: {
      'version': 'v1',
      'endpoints': [
        '/api/v1/users',
        '/api/v1/apps',
        '/api/v1/organizations',
        '/api/v1/diagnostics',
      ],
    },
  );
}
